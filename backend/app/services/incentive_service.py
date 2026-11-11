"""Tutor hours and certificate business logic.

The certificate is an incentive, and it is deliberately a different kind of rule
from the standing in `rating_service`. Promotion answers "can this tutor be
offered work", from ratings and session count; this answers "has this tutor put
in enough hours, over enough sessions, at a good enough standard". Standing is
not read here: a suspended tutor still has the hours they taught, and quietly
withholding them would be a product decision about what a suspension means for an
incentive nobody has written down.

Three conditions, not one. Minutes are the volume, completed sessions are the
record, and the average rating is the quality bar. Counting hours alone let a
tutor who taught four very long sessions collect a certificate that claims a
sustained teaching record, which is what the session-count gate exists to stop.
All three thresholds are configuration rather than constants because they are
things a product owner tunes between pilots, not rules engineering should have to
defend in review. They are read per call rather than captured at import, so
lowering one takes effect on the next request instead of at the next deploy.
"""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.tutor_profile import TutorProfile
from app.models.user import User
from app.schemas.tutor import CertificateEligibilityResponse


async def get_certificate_eligibility(
    db: AsyncSession, user: User
) -> CertificateEligibilityResponse:
    """How close the signed-in user is to a certificate.

    The only subject is the caller. There is no user parameter beyond the
    authenticated one, so there is no question of whose standing is being read:
    an answer about someone else's hours is not a thing this function can
    produce, and `GET /v1/incentives/certificate` takes nothing to change that.

    A user with no `TutorProfile` is answered rather than refused or created
    one. The row belongs to a user holding the tutor role and is created when
    the role is granted, so a missing one means "not a tutor yet" -- a real
    state, not an error, and a student opening the screen should be told their
    hours rather than shown a failure or handed a standing they were never
    assessed for. Creating the row here would be the `rating_service` bug again:
    a read that hands every signed-in student a `probationary` standing and a
    certificate total of zero merely by opening a screen.
    """
    profile = await db.scalar(
        select(TutorProfile).where(TutorProfile.user_id == user.id)
    )
    settings = get_settings()
    required_minutes = settings.certificate_required_minutes
    required_sessions = settings.certificate_required_sessions
    required_average = settings.certificate_minimum_average

    certified = profile.certified_minutes if profile is not None else 0
    completed = profile.completed_sessions if profile is not None else 0
    rating_count = profile.rating_count if profile is not None else 0
    average = profile.average_rating if profile is not None else None

    # Each verdict is a `>=` against the stored value, never against a display
    # rounding. `certified` is an integer and `average` is the exact Decimal the
    # promotion rule also reads, so a tutor exactly on a bar is in and a tutor a
    # hundredth short is out. The three booleans travel to the client so the
    # screen can say which condition is outstanding rather than leaving the tutor
    # to guess from three unrelated numbers.
    minutes_met = certified >= required_minutes
    sessions_met = completed >= required_sessions
    rating_met = (
        rating_count >= required_sessions
        and average is not None
        and average >= required_average
    )

    return CertificateEligibilityResponse(
        has_tutor_profile=profile is not None,
        eligible=minutes_met and sessions_met and rating_met,
        certified_minutes=certified,
        required_minutes=required_minutes,
        remaining_minutes=max(required_minutes - certified, 0),
        completed_sessions=completed,
        required_sessions=required_sessions,
        remaining_sessions=max(required_sessions - completed, 0),
        rating_count=rating_count,
        average_rating=average,
        required_average_rating=required_average,
        minutes_met=minutes_met,
        sessions_met=sessions_met,
        rating_met=rating_met,
        # The bar advances only when every condition does, so a tutor who has
        # taught the hours but not yet the sessions is not shown a full bar
        # beside a "not earned" verdict. The limiting requirement is the honest
        # one to draw.
        progress=min(
            _fraction(certified, required_minutes),
            _fraction(completed, required_sessions),
            _rating_progress(
                average, rating_count, required_sessions, required_average
            ),
        ),
        generated_at=datetime.now(UTC),
    )


def _fraction(value: int, required: int) -> float:
    """A count as a fraction of its threshold, clamped to the 0.0-1.0 wire scale.

    `required` is `gt=0` in configuration for every caller, so the division
    cannot be by zero. The value is clamped here rather than at the client
    because an over-threshold count is the server's fact, and a number above 1.0
    would make `LinearProgressIndicator` throw on the screen that reads it.
    """
    if value >= required:
        return 1.0
    return value / required


def _rating_progress(
    average: Decimal | None,
    count: int,
    required_count: int,
    required_average: Decimal,
) -> float:
    """How far the rating condition is from being met.

    Two things can be short, and they are not interchangeable: a tutor with four
    five-star ratings is closer by evidence than one with ten ratings averaging
    3.0. Until the count is met, the count is what is missing; after that, the
    average is. The average is compared as a `Decimal` and only converted to a
    float for display, so 4.10 is exactly in and 4.099 is exactly out.
    """
    if count < required_count:
        return _fraction(count, required_count)
    if average is None:
        return 0.0
    if average >= required_average:
        return 1.0
    if average <= 0:
        return 0.0
    return float(average / required_average)
