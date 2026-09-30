"""Tutoring session lifecycle business logic."""

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.exceptions import (
    AuthorizationProblem,
    ConflictProblem,
    NotFoundProblem,
    ValidationProblem,
)
from app.models.course_unit import CourseUnit
from app.models.enums import (
    HelpRequestStatus,
    SESSION_TRANSITIONS,
    SessionStatus,
    UserRole,
)
from app.models.session import HelpRequest, Session
from app.models.user import User, has_role, load_roles
from app.schemas.session import (
    SessionCreate,
    SessionResponse,
    SessionTransitionRequest,
)


def _utc(dt: datetime) -> datetime:
    """Normalize to UTC so SQLite and PostgreSQL agree on the same instant."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


async def create_session(
    db: AsyncSession,
    user: User,
    payload: SessionCreate,
) -> SessionResponse:
    """Create a session for a matched help request.

    The session is created by the tutor once the match has been accepted. A
    session without a help request is not the primary flow for the MVP: a real
    tutoring session always starts from a problem the student asked for.
    """
    roles = await load_roles(db, user.id)
    if not has_role(roles, UserRole.TUTOR):
        raise AuthorizationProblem("Only tutors can accept a session.")

    if payload.help_request_id is None:
        raise ValidationProblem(
            "A session must be linked to a help request.",
            errors={"help_request_id": "required"},
        )

    help_request = await _load_help_request(db, payload.help_request_id)
    if help_request.tutee_id == user.id:
        raise AuthorizationProblem("The student cannot create the accepted session.")
    if help_request.matched_tutor_id is not None and help_request.matched_tutor_id != user.id:
        raise AuthorizationProblem("Only the matched tutor can accept this request.")
    if help_request.matched_tutor_id is None:
        help_request.matched_tutor_id = user.id
        help_request.status = HelpRequestStatus.MATCHED

    if help_request.status in {HelpRequestStatus.WITHDRAWN, HelpRequestStatus.EXPIRED}:
        raise ConflictProblem("This help request is no longer active.")

    course_unit = await _load_course_unit(db, payload.course_unit_id)
    if course_unit.id != help_request.course_unit_id:
        raise ValidationProblem(
            "The session course unit must match the help request.",
            errors={"course_unit_id": "must match the request"},
        )

    existing = await db.scalar(
        select(Session.id).where(Session.help_request_id == help_request.id)
    )
    if existing is not None:
        raise ConflictProblem("That help request already has an accepted session.")

    session = Session(
        help_request_id=help_request.id,
        tutee_id=help_request.tutee_id,
        tutor_id=user.id,
        course_unit_id=course_unit.id,
        topic=payload.topic or help_request.topic,
        scheduled_start=payload.scheduled_start,
        duration_minutes=payload.duration_minutes,
        session_pin=Session.generate_session_pin(),
        meeting_link=(payload.meeting_link or "").strip() or None,
        status=SessionStatus.SCHEDULED,
    )
    db.add(session)
    help_request.status = HelpRequestStatus.MATCHED
    help_request.matched_tutor_id = user.id
    await db.flush()
    await db.refresh(session)
    return await _session_response(db, session)


async def list_sessions(
    db: AsyncSession,
    user: User,
    *,
    include_cancelled: bool = True,
) -> list[SessionResponse]:
    """Every session the signed-in user is part of."""
    query = (
        select(Session)
        .where((Session.tutee_id == user.id) | (Session.tutor_id == user.id))
        .options(
            selectinload(Session.help_request),
            selectinload(Session.tutee),
            selectinload(Session.tutor),
            selectinload(Session.course_unit),
        )
        .order_by(Session.created_at.desc())
    )
    if not include_cancelled:
        query = query.where(Session.status != SessionStatus.CANCELLED)
    result = await db.execute(query)
    return [await _session_response(db, row) for row in result.scalars()]


async def get_session(db: AsyncSession, user: User, session_id: uuid.UUID) -> SessionResponse:
    """Fetch one session the current user can view."""
    session = await _load_session_for_user(db, user, session_id)
    return await _session_response(db, session)


async def transition_session(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
    payload: SessionTransitionRequest,
) -> SessionResponse:
    """Move a session through its allowed lifecycle states."""
    session = await _load_session_for_user(db, user, session_id)
    allowed = SESSION_TRANSITIONS.get(session.status, frozenset())
    if payload.status not in allowed:
        raise ValidationProblem(
            "That session status change is not allowed.",
            errors={"status": f"{session.status.value} -> {payload.status.value} is invalid"},
        )

    if payload.status is SessionStatus.IN_PROGRESS:
        if payload.pin is None:
            raise ValidationProblem(
                "The pin is required to start the session.",
                errors={"pin": "required"},
            )
        if payload.pin.strip() != (session.session_pin or ""):
            raise ValidationProblem(
                "The session PIN is incorrect.",
                errors={"pin": "incorrect"},
            )
        session.started_at = _utc(session.started_at or datetime.now(UTC))

    if payload.status is SessionStatus.COMPLETED:
        if session.started_at is None:
            raise ValidationProblem(
                "The session must start before it can be completed.",
                errors={"status": "in_progress required"},
            )
        session.ended_at = _utc(session.ended_at or datetime.now(UTC))
        elapsed = int((_utc(session.ended_at) - _utc(session.started_at)).total_seconds() // 60)
        session.duration_minutes = max(1, elapsed)

    if payload.status is SessionStatus.CANCELLED:
        session.cancelled_by_id = user.id
        session.cancellation_reason = payload.cancellation_reason

    if payload.status is not SessionStatus.CANCELLED:
        session.cancelled_by_id = None
        session.cancellation_reason = None

    session.status = payload.status
    await db.flush()
    return await _session_response(db, session)


async def verify_session_pin(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
    pin: str,
) -> SessionResponse:
    """Verify the two-digit session PIN before the session is marked live."""
    session = await _load_session_for_user(db, user, session_id)
    expected = session.session_pin or ""
    if pin.strip() != expected:
        raise ValidationProblem(
            "The session PIN is incorrect.",
            errors={"pin": "incorrect"},
        )
    if session.status is not SessionStatus.SCHEDULED:
        raise ConflictProblem("This session is not waiting to start.")
    session.status = SessionStatus.IN_PROGRESS
    session.started_at = _utc(session.started_at or datetime.now(UTC))
    await db.flush()
    return await _session_response(db, session)


async def _load_help_request(db: AsyncSession, request_id: uuid.UUID) -> HelpRequest:
    """Fetch one help request, eagerly loading the joined rows it exposes."""
    result = await db.execute(
        select(HelpRequest)
        .where(HelpRequest.public_id == request_id)
        .options(
            selectinload(HelpRequest.tutee),
            selectinload(HelpRequest.course_unit),
            selectinload(HelpRequest.matched_tutor),
        )
    )
    request = result.scalar_one_or_none()
    if request is None:
        raise NotFoundProblem("That help request could not be found.")
    return request


async def _load_course_unit(db: AsyncSession, course_unit_id: uuid.UUID) -> CourseUnit:
    """Fetch one course unit by public id."""
    result = await db.execute(
        select(CourseUnit).where(CourseUnit.public_id == course_unit_id)
    )
    course_unit = result.scalar_one_or_none()
    if course_unit is None:
        raise NotFoundProblem("That course unit could not be found.")
    return course_unit


async def _load_session_for_user(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
) -> Session:
    """Load a session only when the caller is one of the parties."""
    result = await db.execute(
        select(Session)
        .where(Session.public_id == session_id)
        .options(
            selectinload(Session.help_request),
            selectinload(Session.tutee),
            selectinload(Session.tutor),
            selectinload(Session.course_unit),
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise NotFoundProblem("That session could not be found.")
    if session.tutee_id != user.id and session.tutor_id != user.id:
        raise AuthorizationProblem("You do not have access to that session.")
    return session


async def _session_response(db: AsyncSession, session: Session) -> SessionResponse:
    """Build the response with a computed rating flag."""
    return SessionResponse(
        id=session.public_id,
        help_request_id=(session.help_request.public_id if session.help_request else None),
        tutee_id=session.tutee.public_id,
        tutor_id=session.tutor.public_id,
        course_unit_id=session.course_unit.public_id,
        topic=session.topic,
        status=session.status,
        scheduled_start=session.scheduled_start,
        started_at=session.started_at,
        ended_at=session.ended_at,
        duration_minutes=session.duration_minutes,
        session_pin=session.session_pin,
        meeting_link=session.meeting_link,
        is_rated=await session.is_rated(db),
        created_at=session.created_at,
    )
