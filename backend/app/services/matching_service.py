"""Tutor matching business logic."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.exceptions import NotFoundProblem, ValidationProblem
from app.models.competency import Competency
from app.models.course_unit import CourseUnit
from app.models.enums import CompetencyStatus, TutorStanding, UserRole
from app.models.session import HelpRequest
from app.models.user import User, user_roles
from app.schemas.matching import (
    MatchCandidate,
    MatchExclusion,
    MatchRequest,
    MatchResponse,
)
from app.schemas.session import HelpRequestCreate, HelpRequestResponse
from app.schemas.tutor import TutorProfileSummary


async def create_help_request(
    db: AsyncSession,
    user: User,
    payload: HelpRequestCreate,
) -> HelpRequestResponse:
    """Create a help request for one course unit and topic."""
    if user.university_id is None:
        raise ValidationProblem(
            "Choose your university before creating a help request.",
            errors={"university_id": "university is required"},
        )

    course_unit = await _load_course_unit(db, payload.course_unit_id)
    if course_unit.university_id != user.university_id:
        raise ValidationProblem(
            "That course unit does not belong to your university.",
            errors={"course_unit_id": "must match your university"},
        )

    request = HelpRequest(
        tutee_id=user.id,
        course_unit_id=course_unit.id,
        topic=payload.topic,
        description=payload.description,
    )
    db.add(request)
    await db.flush()
    await db.refresh(request)
    return _help_request_response(request)


async def list_help_requests(
    db: AsyncSession,
    user: User,
) -> list[HelpRequestResponse]:
    """Every open help request this student created."""
    result = await db.execute(
        select(HelpRequest)
        .where(HelpRequest.tutee_id == user.id)
        .options(
            selectinload(HelpRequest.course_unit).selectinload(CourseUnit.university),
            selectinload(HelpRequest.matched_tutor),
        )
        .order_by(HelpRequest.created_at.desc())
    )
    return [_help_request_response(row) for row in result.scalars()]


async def match_tutors(
    db: AsyncSession,
    user: User,
    payload: MatchRequest,
) -> MatchResponse:
    """Rank tutors for a course unit and optionally widen to the subject."""
    if user.university_id is None:
        raise ValidationProblem(
            "Choose your university before asking for matches.",
            errors={"university_id": "university is required"},
        )

    target = await _load_course_unit(db, payload.course_unit_id)
    if target.university_id != user.university_id:
        raise ValidationProblem(
            "You can only match tutors from your university.",
            errors={"course_unit_id": "must match your university"},
        )

    candidates, exclusions, widened = await _search_candidates(
        db,
        user=user,
        course_unit=target,
        widen_to_subject=payload.widen_to_subject,
    )

    ranked = sorted(
        candidates,
        key=lambda item: (-item.score, -float(item.competency_grade_points)),
    )[: payload.limit]
    return MatchResponse(
        request_id=uuid.uuid4(),
        course_unit_id=payload.course_unit_id,
        widened=widened,
        candidates=ranked,
        exclusions=exclusions,
        no_eligible_tutors=not ranked,
        generated_at=datetime.now(UTC),
    )


async def match_request_tutors(
    db: AsyncSession,
    user: User,
    request_id: uuid.UUID,
    payload: MatchRequest,
) -> MatchResponse:
    """Compatibility wrapper for a request-backed match query."""
    await _load_help_request(db, user, request_id)
    return await match_tutors(db, user, MatchRequest(**payload.model_dump()))


async def _search_candidates(
    db: AsyncSession,
    *,
    user: User,
    course_unit: CourseUnit,
    widen_to_subject: bool,
) -> tuple[list[MatchCandidate], list[MatchExclusion], bool]:
    """Collect eligible tutors for the exact unit, or a subject fallback."""
    exact_candidates, exact_exclusions = await _search_candidates_for_units(
        db,
        user=user,
        course_units={course_unit.id},
    )
    if exact_candidates or not widen_to_subject:
        return exact_candidates, exact_exclusions, False

    result = await db.execute(
        select(CourseUnit.id).where(
            CourseUnit.university_id == course_unit.university_id,
            CourseUnit.subject_id == course_unit.subject_id,
        )
    )
    subject_unit_ids = set(result.scalars().all())
    fallback_candidates, fallback_exclusions = await _search_candidates_for_units(
        db,
        user=user,
        course_units=subject_unit_ids,
    )
    return fallback_candidates, fallback_exclusions, True


async def _search_candidates_for_units(
    db: AsyncSession,
    *,
    user: User,
    course_units: set[uuid.UUID],
) -> tuple[list[MatchCandidate], list[MatchExclusion]]:
    """Rank eligible tutors across one or many units."""
    candidates: list[MatchCandidate] = []
    exclusions: list[MatchExclusion] = []

    if not course_units:
        return candidates, exclusions

    competencies = await db.execute(
        select(Competency)
        .where(
            Competency.course_unit_id.in_(list(course_units)),
            Competency.status == CompetencyStatus.VERIFIED,
            Competency.user_id != user.id,
        )
        .options(
            selectinload(Competency.user).selectinload(User.tutor_profile),
            selectinload(Competency.user).selectinload(User.university),
            selectinload(Competency.grade),
            selectinload(Competency.course_unit).selectinload(CourseUnit.university),
            selectinload(Competency.course_unit).selectinload(CourseUnit.subject),
        )
        .order_by(Competency.created_at.desc())
    )

    for competency in competencies.scalars():
        tutor = competency.user
        if tutor.id == user.id:
            continue
        if not await _has_role(db, tutor.id, UserRole.TUTOR):
            continue
        if tutor.university_id != user.university_id:
            exclusions.append(
                MatchExclusion(tutor_id=tutor.public_id, reason="same_university_only")
            )
            continue

        profile = tutor.tutor_profile
        if profile is not None and profile.standing is TutorStanding.SUSPENDED:
            exclusions.append(
                MatchExclusion(tutor_id=tutor.public_id, reason="suspended")
            )
            continue

        threshold = _grade_threshold(competency.course_unit)
        if competency.grade.grade_points < threshold:
            exclusions.append(
                MatchExclusion(tutor_id=tutor.public_id, reason="below_threshold")
            )
            continue

        if profile is None:
            exclusions.append(
                MatchExclusion(tutor_id=tutor.public_id, reason="not_the_tutor")
            )
            continue

        score = float(competency.grade.grade_points)
        if profile.average_rating is not None:
            score += float(profile.average_rating) / 10
        if profile.standing is TutorStanding.VERIFIED:
            score += 2.0
        elif profile.standing is TutorStanding.REDUCED:
            score -= 1.0

        candidates.append(
            MatchCandidate(
                tutor=TutorProfileSummary(
                    user_id=tutor.public_id,
                    full_name=tutor.full_name or tutor.email,
                    standing=profile.standing,
                    average_rating=profile.average_rating,
                    completed_sessions=profile.completed_sessions,
                ),
                course_unit_id=competency.course_unit.public_id,
                competency_grade_points=competency.grade.grade_points,
                meets_threshold=True,
                score=score,
            )
        )

    unique_candidates: dict[uuid.UUID, MatchCandidate] = {}
    for candidate in candidates:
        unique_candidates[candidate.tutor.user_id] = candidate
    unique_exclusions: list[MatchExclusion] = []
    seen: set[tuple[uuid.UUID, str]] = set()
    for exclusion in exclusions:
        key = (exclusion.tutor_id, exclusion.reason)
        if key not in seen:
            seen.add(key)
            unique_exclusions.append(exclusion)

    ranked_candidates = sorted(
        unique_candidates.values(),
        key=lambda item: (-item.score, -float(item.competency_grade_points)),
    )
    return ranked_candidates, unique_exclusions


async def _load_course_unit(db: AsyncSession, public_id: uuid.UUID) -> CourseUnit:
    result = await db.execute(
        select(CourseUnit)
        .where(CourseUnit.public_id == public_id)
        .options(
            selectinload(CourseUnit.university),
            selectinload(CourseUnit.subject),
            selectinload(CourseUnit.grade),
        )
    )
    course_unit = result.scalar_one_or_none()
    if course_unit is None:
        raise NotFoundProblem("That course unit could not be found.")
    return course_unit


async def _has_role(db: AsyncSession, user_id: uuid.UUID, role: UserRole) -> bool:
    result = await db.execute(
        select(user_roles.c.role).where(
            user_roles.c.user_id == user_id, user_roles.c.role == role.value
        )
    )
    return result.scalar_one_or_none() is not None


def _grade_threshold(course_unit: CourseUnit) -> Decimal:
    scale = course_unit.university.grading_scale
    if scale is None:
        return Decimal("0")
    return scale.competency_min_points


async def _load_help_request(
    db: AsyncSession,
    user: User,
    public_id: uuid.UUID,
) -> HelpRequest:
    result = await db.execute(
        select(HelpRequest)
        .where(HelpRequest.public_id == public_id, HelpRequest.tutee_id == user.id)
        .options(
            selectinload(HelpRequest.course_unit),
            selectinload(HelpRequest.matched_tutor),
        )
    )
    request = result.scalar_one_or_none()
    if request is None:
        raise NotFoundProblem("That help request could not be found.")
    return request


def _help_request_response(request: HelpRequest) -> HelpRequestResponse:
    return HelpRequestResponse.model_validate(
        {
            "id": request.public_id,
            "tutee_id": request.tutee_public_id,
            "course_unit_id": request.course_unit_public_id,
            "topic": request.topic,
            "description": request.description,
            "status": request.status,
            "matched_tutor_id": request.matched_tutor_public_id,
            "created_at": request.created_at,
        }
    )
