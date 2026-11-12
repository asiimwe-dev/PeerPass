"""Tutor hours and per-course certificate business logic.

A certificate is earned per course, not per tutor. The hours, completed
sessions, and ratings that count are the ones recorded against that course unit,
so a tutor who teaches three courses has three separate certificates to work on
and one very long course cannot carry the others over the bar.

The three conditions are the same for every course. Minutes are the volume,
completed sessions are the record, and the average rating is the quality bar.
Counting hours alone let a tutor who taught four very long sessions collect a
certificate that claims a sustained teaching record, which is what the
session-count gate exists to stop. All three thresholds are configuration rather
than constants because they are things a product owner tunes between pilots, not
rules engineering should have to defend in review. They are read per call rather
than captured at import, so lowering one takes effect on the next request
instead of at the next deploy.

Which courses appear:

* every course with a **verified** competency, even with no sessions yet, so a
  new tutor sees the target they are working towards;
* every course with a completed session as tutor, even if the competency is no
  longer verified, because the teaching happened and an incentive must not erase
  a record when an administrative status changes;
* nothing else. A pending or rejected competency with no sessions is a claim,
  not a certificate in progress.

These are derived from `sessions.course_unit_id` and the ratings attached to
those sessions rather than from `TutorProfile`'s counters. The profile counters
are a tutor-wide total and are exactly the number a per-course answer must not
use.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.competency import Competency
from app.models.course_unit import CourseUnit
from app.models.enums import CompetencyStatus, SessionStatus
from app.models.rating import Rating
from app.models.session import Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User
from app.schemas.tutor import (
    CertificateEligibilityResponse,
    CertificatePortfolioResponse,
    CourseCertificateResponse,
)


@dataclass(frozen=True)
class _Evidence:
    """What one course has banked so far."""

    minutes: int = 0
    sessions: int = 0
    rating_count: int = 0
    #: Sum of every score, so the mean can be computed exactly as a `Decimal`
    #: rather than read from a database `avg()` that returns a float on SQLite
    #: and a `numeric` on PostgreSQL.
    rating_score: int = 0


@dataclass(frozen=True)
class _Portfolio:
    """The wire response plus the pieces an aggregate summary needs."""

    response: CertificatePortfolioResponse


async def get_certificate_portfolio(
    db: AsyncSession, user: User
) -> CertificatePortfolioResponse:
    """Every course the caller can earn a certificate for, closest first.

    The only subject is the caller. There is no user parameter beyond the
    authenticated one, so there is no question of whose standing is being read:
    an answer about someone else's hours is not a thing this function can
    produce, and `GET /v1/incentives/certificate` takes nothing to change that.
    """
    return (await _build_portfolio(db, user)).response


async def get_certificate_eligibility(
    db: AsyncSession, user: User
) -> CertificateEligibilityResponse:
    """A single-course summary for the tutor HQ, not a separate rule.

    The dashboard has one certificate card and the portfolio can hold several
    courses, so the card describes the course the tutor is closest to earning:
    the portfolio is ordered earned first, then by progress. The flags and the
    bar come from that course unchanged, which keeps the HQ from disagreeing
    with the certificate screen about a threshold or a verdict.

    A caller with no courses gets zeros, false flags, and a full shortfall, which
    is the same shape a student with no tutor profile gets. The
    `has_tutor_profile` flag is what separates the two on the wire.
    """
    portfolio = await _build_portfolio(db, user)
    settings = get_settings()
    required_minutes = settings.certificate_required_minutes
    required_sessions = settings.certificate_required_sessions
    required_average = settings.certificate_minimum_average

    best = portfolio.response.courses[0] if portfolio.response.courses else None
    if best is None:
        return CertificateEligibilityResponse(
            has_tutor_profile=portfolio.response.has_tutor_profile,
            eligible=False,
            certified_minutes=0,
            required_minutes=required_minutes,
            remaining_minutes=required_minutes,
            completed_sessions=0,
            required_sessions=required_sessions,
            remaining_sessions=required_sessions,
            rating_count=0,
            average_rating=None,
            required_average_rating=required_average,
            minutes_met=False,
            sessions_met=False,
            rating_met=False,
            progress=0.0,
            generated_at=portfolio.response.generated_at,
        )

    return CertificateEligibilityResponse(
        has_tutor_profile=portfolio.response.has_tutor_profile,
        eligible=best.eligible,
        certified_minutes=best.certified_minutes,
        required_minutes=best.required_minutes,
        remaining_minutes=best.remaining_minutes,
        completed_sessions=best.completed_sessions,
        required_sessions=best.required_sessions,
        remaining_sessions=best.remaining_sessions,
        rating_count=best.rating_count,
        average_rating=best.average_rating,
        required_average_rating=best.required_average_rating,
        minutes_met=best.minutes_met,
        sessions_met=best.sessions_met,
        rating_met=best.rating_met,
        progress=best.progress,
        generated_at=portfolio.response.generated_at,
    )


async def _build_portfolio(db: AsyncSession, user: User) -> _Portfolio:
    settings = get_settings()
    required_minutes = settings.certificate_required_minutes
    required_sessions = settings.certificate_required_sessions
    required_average = settings.certificate_minimum_average

    has_profile = (
        await db.scalar(
            select(TutorProfile.id).where(TutorProfile.user_id == user.id).limit(1)
        )
    ) is not None

    units: dict[uuid.UUID, CourseUnit] = {}
    verified_units = (
        await db.execute(
            select(CourseUnit)
            .join(Competency, Competency.course_unit_id == CourseUnit.id)
            .where(
                Competency.user_id == user.id,
                Competency.status == CompetencyStatus.VERIFIED,
            )
        )
    ).scalars()
    for unit in verified_units:
        units[unit.id] = unit

    session_rows = await db.execute(
        select(
            Session.course_unit_id,
            func.count(Session.id),
            # `max(duration_minutes, 0)`, in SQL: a repaired row with a negative
            # duration must not subtract from a certificate the tutor earned.
            func.coalesce(
                func.sum(
                    case(
                        (Session.duration_minutes > 0, Session.duration_minutes),
                        else_=0,
                    )
                ),
                0,
            ),
        )
        .where(
            Session.tutor_id == user.id,
            Session.status == SessionStatus.COMPLETED,
        )
        .group_by(Session.course_unit_id)
    )
    session_evidence: dict[uuid.UUID, _Evidence] = {
        course_unit_id: _Evidence(
            minutes=int(minutes or 0), sessions=int(sessions or 0)
        )
        for course_unit_id, sessions, minutes in session_rows
    }

    rating_rows = await db.execute(
        select(
            Session.course_unit_id,
            func.count(Rating.id),
            func.coalesce(func.sum(Rating.score), 0),
        )
        .join(Rating, Rating.session_id == Session.id)
        .where(
            Session.tutor_id == user.id,
            Session.status == SessionStatus.COMPLETED,
            Rating.ratee_id == user.id,
        )
        .group_by(Session.course_unit_id)
    )
    rating_evidence: dict[uuid.UUID, tuple[int, int]] = {
        course_unit_id: (int(count or 0), int(score or 0))
        for course_unit_id, count, score in rating_rows
    }

    # A course earned its way in through a session but not through a still-
    # verified competency. Load those units too, so the evidence is not dropped
    # merely because the claim's status changed.
    missing = {
        course_unit_id
        for course_unit_id in session_evidence.keys() | rating_evidence.keys()
        if course_unit_id not in units
    }
    if missing:
        for unit in (
            await db.execute(select(CourseUnit).where(CourseUnit.id.in_(missing)))
        ).scalars():
            units[unit.id] = unit

    courses: list[CourseCertificateResponse] = []
    for unit in units.values():
        session_part = session_evidence.get(unit.id, _Evidence())
        rating_count, rating_score = rating_evidence.get(unit.id, (0, 0))
        average = (
            Decimal(rating_score) / Decimal(rating_count) if rating_count else None
        )

        minutes_met = session_part.minutes >= required_minutes
        sessions_met = session_part.sessions >= required_sessions
        rating_met = (
            rating_count >= required_sessions
            and average is not None
            and average >= required_average
        )

        courses.append(
            CourseCertificateResponse(
                course_unit_id=unit.public_id,
                course_unit_code=unit.code,
                course_unit_name=unit.name,
                eligible=minutes_met and sessions_met and rating_met,
                certified_minutes=session_part.minutes,
                required_minutes=required_minutes,
                remaining_minutes=max(required_minutes - session_part.minutes, 0),
                completed_sessions=session_part.sessions,
                required_sessions=required_sessions,
                remaining_sessions=max(required_sessions - session_part.sessions, 0),
                rating_count=rating_count,
                average_rating=average,
                required_average_rating=required_average,
                minutes_met=minutes_met,
                sessions_met=sessions_met,
                rating_met=rating_met,
                progress=min(
                    _fraction(session_part.minutes, required_minutes),
                    _fraction(session_part.sessions, required_sessions),
                    _rating_progress(
                        average,
                        rating_count,
                        required_sessions,
                        required_average,
                    ),
                ),
            )
        )

    # Earned first, then closest to earned, then code. The ordering is the
    # server's because the dashboard's one-card summary reads the first entry,
    # and a rule duplicated in two clients is a rule that can disagree with
    # itself on the two screens.
    courses.sort(
        key=lambda course: (
            not course.eligible,
            -course.progress,
            course.course_unit_code,
            course.course_unit_name,
        )
    )

    return _Portfolio(
        response=CertificatePortfolioResponse(
            has_tutor_profile=has_profile,
            courses=courses,
            generated_at=datetime.now(UTC),
        )
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
