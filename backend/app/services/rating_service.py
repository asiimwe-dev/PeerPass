"""Tutor rating and standing updates."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.exceptions import (
    AuthorizationProblem,
    NotFoundProblem,
    ValidationProblem,
)
from app.models.enums import SessionStatus, TutorStanding
from app.models.rating import Rating
from app.models.session import Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User
from app.schemas.rating import RatingCreate, RatingResponse, TutorRatingSummary

PROMOTION_MIN_SESSIONS = 3
PROMOTION_MIN_AVERAGE = Decimal("4.10")


async def submit_rating(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
    payload: RatingCreate,
) -> RatingResponse:
    """Write or update a session rating and recalculate the tutor's standing."""
    session = await _load_session_for_user(db, user, session_id)
    if session.status is not SessionStatus.COMPLETED:
        raise ValidationProblem(
            "Only completed sessions can be rated.",
            errors={"session_id": "must be completed"},
        )

    if user.id not in {session.tutee_id, session.tutor_id}:
        raise AuthorizationProblem("You are not part of this session.")

    ratee_id = session.tutor_id if user.id == session.tutee_id else session.tutee_id
    result = await db.execute(
        select(Rating)
        .where(Rating.session_id == session.id, Rating.rater_id == user.id)
        .options(
            selectinload(Rating.session),
            selectinload(Rating.rater),
            selectinload(Rating.ratee),
        )
    )
    existing = result.scalar_one_or_none()

    if existing is None:
        rating = Rating(
            session_id=session.id,
            rater_id=user.id,
            ratee_id=ratee_id,
            score=payload.score,
            feedback_text=payload.feedback_text,
        )
        db.add(rating)
        profile = await _get_or_create_tutor_profile(db, ratee_id)
        profile.rating_total += Decimal(str(payload.score))
        profile.rating_count += 1
        await _recompute_standing(db, profile)
        await db.flush()
        await db.refresh(rating)
        return RatingResponse.model_validate(rating)

    previous_score = Decimal(str(existing.score))
    existing.score = payload.score
    existing.feedback_text = payload.feedback_text
    profile = await _get_or_create_tutor_profile(db, ratee_id)
    profile.rating_total = (
        profile.rating_total - previous_score + Decimal(str(payload.score))
    )
    await _recompute_standing(db, profile)
    await db.flush()
    await db.refresh(existing)
    return RatingResponse.model_validate(existing)


async def get_tutor_rating_summary(
    db: AsyncSession,
    user: User,
) -> TutorRatingSummary:
    """The aggregate rating summary the tutor profile is built from."""
    profile = await _get_or_create_tutor_profile(db, user.id)
    result = await db.execute(
        select(Rating)
        .where(Rating.ratee_id == user.id)
        .options(
            selectinload(Rating.session),
            selectinload(Rating.rater),
            selectinload(Rating.ratee),
        )
        .order_by(Rating.created_at.desc())
        .limit(20)
    )
    recent = [RatingResponse.model_validate(row) for row in result.scalars()]
    return TutorRatingSummary(
        average_rating=profile.average_rating,
        rating_total=profile.rating_total,
        rating_count=profile.rating_count,
        recent=recent,
    )


async def _load_session_for_user(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
) -> Session:
    result = await db.execute(
        select(Session)
        .where(Session.public_id == session_id)
        .options(
            selectinload(Session.tutee),
            selectinload(Session.tutor),
            selectinload(Session.course_unit),
            selectinload(Session.help_request),
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise NotFoundProblem("That session could not be found.")
    if session.tutee_id != user.id and session.tutor_id != user.id:
        raise AuthorizationProblem("You are not part of that session.")
    return session


async def _get_or_create_tutor_profile(
    db: AsyncSession, user_id: uuid.UUID
) -> TutorProfile:
    result = await db.execute(
        select(TutorProfile).where(TutorProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()
    if profile is None:
        profile = TutorProfile(user_id=user_id)
        db.add(profile)
        await db.flush()
    return profile


async def _recompute_standing(db: AsyncSession, profile: TutorProfile) -> None:
    if (
        profile.completed_sessions < PROMOTION_MIN_SESSIONS
        or profile.average_rating is None
    ):
        profile.standing = TutorStanding.PROBATIONARY
        return

    if profile.average_rating >= PROMOTION_MIN_AVERAGE:
        profile.standing = TutorStanding.VERIFIED
    else:
        profile.standing = TutorStanding.REDUCED


async def record_completion(db: AsyncSession, session: Session) -> None:
    """Persist the completed-session counters that support promotion and
    certificate totals.
    """
    if session.status is not SessionStatus.COMPLETED:
        return
    profile = await _get_or_create_tutor_profile(db, session.tutor_id)
    profile.completed_sessions += 1
    profile.certified_minutes += max(session.duration_minutes, 0)
    await _recompute_standing(db, profile)


async def list_recent_ratings(
    db: AsyncSession,
    user: User,
    *,
    limit: int = 20,
) -> list[RatingResponse]:
    """Most recent ratings received by the current tutor."""
    result = await db.execute(
        select(Rating)
        .where(Rating.ratee_id == user.id)
        .options(
            selectinload(Rating.session),
            selectinload(Rating.rater),
            selectinload(Rating.ratee),
        )
        .order_by(Rating.created_at.desc())
        .limit(limit)
    )
    return [RatingResponse.model_validate(row) for row in result.scalars()]
