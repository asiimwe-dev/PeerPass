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
    SESSION_TRANSITIONS,
    HelpRequestStatus,
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
from app.services import notification_service, rating_service


def _utc(dt: datetime) -> datetime:
    """Normalize to UTC so SQLite and PostgreSQL agree on the same instant."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def _attendance_minutes(
    started_at: datetime,
    tutor_finished_at: datetime,
    tutee_finished_at: datetime,
) -> int:
    """Whole minutes both parties were present, with a floor of one.

    The end of the window is the *earlier* finish, not the later one. Hours
    banked behind a certificate have to be defensible, and the time after one
    participant left is not time that participant can confirm. A party who
    forgets to tap finish until an hour later must not extend the session; the
    other party's timestamp is the ceiling.

    The floor of one minute keeps a check-in-and-finish in the same minute from
    recording a session with no time in it. Such a session still counts towards
    promotion, so it must not be able to contribute zero hours to a certificate.
    """
    ended_at = min(_utc(tutor_finished_at), _utc(tutee_finished_at))
    return max(1, int((ended_at - _utc(started_at)).total_seconds() // 60))


async def create_session(
    db: AsyncSession,
    user: User,
    payload: SessionCreate,
) -> SessionResponse:
    """Confirm a selected help request and create the session for it.

    The tutor confirms; they do not claim. A session used to be creatable by any
    tutor against any unselected request, which set `matched_tutor_id` to the
    caller and left the student never asked -- the inverse of MVP decision 3, and
    the one place a tutor could take work the student had refused them. Only the
    tutor the student already named may confirm, and only from the state that says
    the student is waiting on them.

    The session is not the primary flow for the MVP: a real tutoring session always
    starts from a problem the student asked for.
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
    if help_request.matched_tutor_id != user.id:
        raise AuthorizationProblem(
            "Only the tutor the student chose can confirm this request."
        )
    # One confirmation per request, and only out of `PENDING_CONFIRMATION`. This
    # is also where `MATCHED` is refused: a retried POST is ordinary on a phone,
    # and re-accepting would hand the student a second session for one question.
    if help_request.status is not HelpRequestStatus.PENDING_CONFIRMATION:
        raise ConflictProblem(
            "This help request is not waiting for this tutor's confirmation."
        )

    course_unit = await _load_course_unit(db, payload.course_unit_id)
    if course_unit.id != help_request.course_unit_id:
        raise ValidationProblem(
            "The session course unit must match the help request.",
            errors={"course_unit_id": "must match the request"},
        )

    # The `session_per_request` unique constraint is the real guarantee -- two
    # simultaneous requests would both pass a check made of a read -- and this is
    # what turns the loser of that race into a 409 rather than a 500.
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
        meeting_link=(payload.meeting_link or "").strip() or None,
        meeting_venue=(payload.meeting_venue or "").strip() or None,
        meeting_venue_detail=(payload.meeting_venue_detail or "").strip() or None,
        status=SessionStatus.SCHEDULED,
    )
    db.add(session)
    help_request.status = HelpRequestStatus.MATCHED
    help_request.matched_tutor_id = user.id
    await db.flush()
    await notification_service.request_accepted(
        db,
        tutee_id=session.tutee_id,
        tutor=user,
        topic=session.topic,
        session_id=session.public_id,
    )
    await db.commit()
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


async def get_session(
    db: AsyncSession, user: User, session_id: uuid.UUID
) -> SessionResponse:
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
            errors={
                "status": f"{session.status.value} -> {payload.status.value} is invalid"
            },
        )

    if payload.status is SessionStatus.IN_PROGRESS:
        # Starting is two check-ins, not a status a caller can set. This used to
        # be reachable with a PIN inline, which let one party declare the other
        # present; now the only way in is `check_in`, called by both accounts.
        raise ValidationProblem(
            "Both parties must check in to start this session.",
            errors={"status": "in_progress requires both check-ins"},
        )

    if payload.status is SessionStatus.COMPLETED:
        raise ValidationProblem(
            "Both parties must finish the session to complete it.",
            errors={"status": "completion requires both finishes"},
        )

    if payload.status is SessionStatus.CANCELLED:
        session.cancelled_by_id = user.id
        session.cancellation_reason = payload.cancellation_reason

    if payload.status is not SessionStatus.CANCELLED:
        session.cancelled_by_id = None
        session.cancellation_reason = None

    # The status is assigned before `record_completion` runs, not after. That
    # function banks minutes only for a session that is already `completed` and
    # returns early otherwise, so calling it against the pre-transition row
    # silently did nothing: no session ever accrued a minute, `completed_sessions`
    # stayed at zero, and with it `_recompute_standing` held every tutor at
    # `probationary` forever. `SESSION_TRANSITIONS` gives `completed` an empty
    # allowed set, so arriving here with this status means the row was not
    # already completed and the accrual happens exactly once.
    session.status = payload.status
    if payload.status is SessionStatus.COMPLETED:
        await rating_service.record_completion(db, session)
    elif payload.status is SessionStatus.CANCELLED:
        # The caller recorded themselves as the canceller just above, so the
        # recipient is never themselves. A cancellation the other party learns
        # about only by opening the session is a no-show waiting to happen.
        recipient_id = (
            session.tutor_id if user.id == session.tutee_id else session.tutee_id
        )
        await notification_service.session_cancelled(
            db,
            recipient_id=recipient_id,
            cancelled_by=user,
            topic=session.topic,
            reason=session.cancellation_reason,
            session_id=session.public_id,
        )

    await db.flush()
    await db.commit()
    return await _session_response(db, session)


async def check_in(
    db: AsyncSession, user: User, session_id: uuid.UUID
) -> SessionResponse:
    """Record one party's arrival, starting the session when both are present.

    Each party writes only their own timestamp. A retried tap after it was
    recorded is idempotent rather than an error: a phone on a slow connection
    retrying a check-in is ordinary, and showing a failure for a state the
    caller already achieved is worse than doing nothing.

    The session becomes live on the second check-in, never the first. That is
    the whole difference from the PIN handshake: there is no code one person
    reads to another, only two accounts independently saying they are here.
    """
    session = await _load_session_for_user(db, user, session_id)
    if session.status in {
        SessionStatus.COMPLETED,
        SessionStatus.CANCELLED,
        SessionStatus.NO_SHOW,
    }:
        raise ConflictProblem("This session is no longer open for check-in.")

    # Serialize the two arrivals. Without the lock both parties can read
    # `scheduled`, each write only their own column, and the second commit
    # overwrites the first -- leaving one check-in recorded and a session that
    # never went live even though both people tapped.
    session = await _lock_session(db, session)
    if session.status in {
        SessionStatus.COMPLETED,
        SessionStatus.CANCELLED,
        SessionStatus.NO_SHOW,
    }:
        # Re-checked under the lock: a cancellation committed between the read
        # above and this write must not leave a check-in on a cancelled session.
        raise ConflictProblem("This session is no longer open for check-in.")

    now = _utc(datetime.now(UTC))
    is_tutor = session.tutor_id == user.id
    already_checked_in = (
        session.tutor_checked_in_at if is_tutor else session.tutee_checked_in_at
    )
    if already_checked_in is None:
        if is_tutor:
            session.tutor_checked_in_at = now
        else:
            session.tutee_checked_in_at = now

    if (
        session.status is SessionStatus.SCHEDULED
        and session.tutor_checked_in_at is not None
        and session.tutee_checked_in_at is not None
    ):
        session.status = SessionStatus.IN_PROGRESS
        session.started_at = _utc(datetime.now(UTC))
        # Tell the party who was already waiting. The caller was present for
        # their own tap, so a notification to them would only repeat the screen
        # they are looking at.
        recipient_id = session.tutee_id if is_tutor else session.tutor_id
        await notification_service.session_started(
            db,
            recipient_id=recipient_id,
            checked_in=user,
            topic=session.topic,
            session_id=session.public_id,
        )

    await db.flush()
    await db.commit()
    return await _session_response(db, session)


async def finish(
    db: AsyncSession, user: User, session_id: uuid.UUID
) -> SessionResponse:
    """Record one party's departure, completing the session when both are done.

    Finishing is refused until the session is live, so nobody can end a session
    the other party never joined. The first finish leaves the session in
    progress; the second completes it, and only then are minutes banked.

    A retried finish after completion is a no-op. A client that did not receive
    the response is the normal case on a metered connection, and re-sending the
    request must not re-bank the session.
    """
    session = await _load_session_for_user(db, user, session_id)
    if session.status is SessionStatus.COMPLETED:
        return await _session_response(db, session)
    if session.status is not SessionStatus.IN_PROGRESS:
        raise ConflictProblem(
            "Only a session both parties have checked in to can be finished."
        )

    session = await _lock_session(db, session)
    if session.status is SessionStatus.COMPLETED:
        return await _session_response(db, session)
    if session.status is not SessionStatus.IN_PROGRESS:
        raise ConflictProblem(
            "Only a session both parties have checked in to can be finished."
        )

    now = _utc(datetime.now(UTC))
    is_tutor = session.tutor_id == user.id
    already_finished = (
        session.tutor_finished_at if is_tutor else session.tutee_finished_at
    )
    if already_finished is None:
        if is_tutor:
            session.tutor_finished_at = now
        else:
            session.tutee_finished_at = now

    if session.tutor_finished_at is not None and session.tutee_finished_at is not None:
        if session.started_at is None:
            # Unreachable through the service -- both check-ins set it -- but
            # failing closed is cheaper than computing minutes from a missing
            # start and banking a nonsense duration if that ever changes.
            raise ConflictProblem("This session has no recorded start.")
        session.ended_at = min(
            _utc(session.tutor_finished_at),
            _utc(session.tutee_finished_at),
        )
        session.duration_minutes = _attendance_minutes(
            session.started_at,
            session.tutor_finished_at,
            session.tutee_finished_at,
        )
        session.status = SessionStatus.COMPLETED
        await rating_service.record_completion(db, session)
        # The tutee is the only party who rates, so the only party who needs the
        # prompt. Deduplicated by key, so finishing twice cannot produce two.
        await notification_service.session_completed(
            db,
            tutee_id=session.tutee_id,
            tutor=session.tutor,
            topic=session.topic,
            session_id=session.public_id,
        )

    await db.flush()
    await db.commit()
    return await _session_response(db, session)


async def _lock_session(db: AsyncSession, session: Session) -> Session:
    """Reload the row under a write lock, with the joins the response needs."""
    result = await db.execute(
        select(Session)
        .where(Session.id == session.id)
        .options(
            selectinload(Session.help_request),
            selectinload(Session.tutee),
            selectinload(Session.tutor),
            selectinload(Session.course_unit),
        )
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    return result.scalar_one()


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
        help_request_id=(
            session.help_request.public_id if session.help_request else None
        ),
        tutee_id=session.tutee.public_id,
        tutor_id=session.tutor.public_id,
        course_unit_id=session.course_unit.public_id,
        course_unit_code=session.course_unit.code,
        course_unit_name=session.course_unit.name,
        # `display_name`, not `full_name`: a deleted account is anonymised to a
        # tombstone with no name, and the other party still has a session with
        # that person in their history. Showing a blank row would erase the
        # evidence from the tutor's screen as surely as deleting the session.
        tutee_name=session.tutee.display_name,
        tutor_name=session.tutor.display_name,
        topic=session.topic,
        status=session.status,
        scheduled_start=session.scheduled_start,
        started_at=session.started_at,
        ended_at=session.ended_at,
        tutor_checked_in_at=session.tutor_checked_in_at,
        tutee_checked_in_at=session.tutee_checked_in_at,
        tutor_finished_at=session.tutor_finished_at,
        tutee_finished_at=session.tutee_finished_at,
        duration_minutes=session.duration_minutes,
        meeting_link=session.meeting_link,
        meeting_venue=session.meeting_venue,
        meeting_venue_detail=session.meeting_venue_detail,
        is_rated=await session.is_rated(db),
        created_at=session.created_at,
    )
