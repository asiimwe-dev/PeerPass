"""Tutor matching business logic.

The gate lives here and only here. `match_tutors` and `match_request_tutors` are
one query with two entry points, because a help request and a course unit are
the same question asked from two screens, and two copies of the eligibility
rules are two copies to drift.
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.exceptions import NotFoundProblem, ValidationProblem
from app.models.competency import Competency
from app.models.course_unit import CourseUnit
from app.models.enums import TutorStanding, UserRole
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
    return help_request_response(request)


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
    return [help_request_response(row) for row in result.scalars()]


async def get_help_request(
    db: AsyncSession,
    user: User,
    request_id: uuid.UUID,
) -> HelpRequestResponse:
    """One help request the student owns.

    Public rather than something the route assembles from two internals: the
    ownership check and the response shape are one decision, and a route that
    reached into the service for them would be able to skip the check by calling
    the wrong half.
    """
    request = await load_help_request(db, user, request_id)
    return help_request_response(request)


async def match_tutors(
    db: AsyncSession,
    user: User,
    payload: MatchRequest,
) -> MatchResponse:
    """Rank tutors for a course unit and optionally widen to the subject.

    Answers `request_id: null`, because nothing backs this query. The field is
    nullable for exactly that reason: an id minted here would name no row, and a
    client that stored it would open `GET /help-requests/{id}` to a 404 and
    conclude the platform lost the request it just made.
    """
    return await _match_for_unit(
        db,
        user,
        course_unit_id=payload.course_unit_id,
        widen_to_subject=payload.widen_to_subject,
        limit=payload.limit,
        request_id=None,
    )


async def match_request_tutors(
    db: AsyncSession,
    user: User,
    request_id: uuid.UUID,
    payload: MatchRequest,
) -> MatchResponse:
    """Rank tutors for the course unit the help request itself names.

    The request is the subject of the query, not a check in front of an
    unrelated one. This was a labelled compatibility wrapper that ignored the
    request it was handed apart from loading it, so a client asking "who can
    take *this* request" got the answer for whichever unit it happened to send
    in the body -- the tutor who could help with something else entirely, or
    none at all, for a request that had eligible tutors.

    A body naming a different unit is refused rather than preferred. Silently
    choosing the request's unit would leave a client that sent the wrong one
    displaying results for a unit it did not ask about, which is the same defect
    wearing a different hat; the rejection names `course_unit_id` so the app can
    put the message next to the field that caused it.
    """
    request = await load_help_request(db, user, request_id)
    if payload.course_unit_id != request.course_unit_public_id:
        raise ValidationProblem(
            "That help request is about a different course unit.",
            errors={
                "course_unit_id": (
                    "must be the course unit this help request was created for"
                )
            },
        )

    return await _match_for_unit(
        db,
        user,
        course_unit_id=payload.course_unit_id,
        widen_to_subject=payload.widen_to_subject,
        limit=payload.limit,
        request_id=request.public_id,
    )


async def _match_for_unit(
    db: AsyncSession,
    user: User,
    *,
    course_unit_id: uuid.UUID,
    widen_to_subject: bool,
    limit: int,
    request_id: uuid.UUID | None,
) -> MatchResponse:
    """The one matching query, whether or not a help request backs it.

    Shared so the two routes cannot drift on the gate: `request_id` is the only
    thing that differs between a request-backed answer and a browse for a unit,
    and a second copy of the eligibility rules is a second copy to get wrong.
    """
    if user.university_id is None:
        raise ValidationProblem(
            "Choose your university before asking for matches.",
            errors={"university_id": "university is required"},
        )

    target = await _load_course_unit(db, course_unit_id)
    if target.university_id != user.university_id:
        raise ValidationProblem(
            "You can only match tutors from your university.",
            errors={"course_unit_id": "must match your university"},
        )

    candidates, exclusions, widened = await _search_candidates(
        db,
        user=user,
        course_unit=target,
        widen_to_subject=widen_to_subject,
    )

    # The search hands them back in rank order, so slicing is all that is left.
    ranked = candidates[:limit]
    return MatchResponse(
        request_id=request_id,
        course_unit_id=course_unit_id,
        widened=widened,
        candidates=ranked,
        exclusions=exclusions,
        no_eligible_tutors=not ranked,
        generated_at=datetime.now(UTC),
    )


def _candidate_rank_key(
    candidate: MatchCandidate, course_unit_code: str
) -> tuple[float, float, str, str]:
    """Sort key for candidates, and for choosing between two rows for one tutor.

    Score first, then the grade behind it, then the tutor's name and the course
    unit's code: the last two exist so that two candidates identical in every
    ranked respect always come out in the same order. Without them the order of
    a widened search would depend on the query plan, and a test asserting on it
    would flake on a backend it had not been run against.

    Both are the *displayed* values, so the tiebreak reads in the same order the
    student sees. The unit's **code** rather than its public id, which is the
    other candidate for the last key: a UUID is random, so ordering by it is
    deterministic and meaningless, and it would keep a tutor in two units of the
    same subject from ever holding the alphabetically first one.
    """
    return (
        -candidate.score,
        -float(candidate.competency_grade_points),
        candidate.tutor.full_name,
        course_unit_code,
    )


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
    """Rank eligible tutors across one or many units.

    A widened search returns one candidate per tutor, not one per competency: a
    tutor competent in three units of a subject is one suggestion, and listing
    them three times would push three weaker tutors off a page the student is
    choosing from. Which of their units is kept is their strongest qualifying
    one -- see `_candidate_rank_key`.

    Returned in rank order, so the caller slices rather than sorting again.

    The tutor role is resolved by joining `user_roles` rather than by asking per
    row. The check was one query per competency, so a widened search across a
    large subject issued one round trip per row before producing the same answer
    a single join gives.

    Pending competencies are read rather than filtered out, because an exclusion
    is the only thing a tutor learns from a result they are not in. A grade
    nobody has checked is the commonest reason a tutor does not appear, and
    dropping the row silently made that unanswerable.
    """
    if not course_units:
        return [], []

    competencies = await db.execute(
        select(Competency)
        .join(
            user_roles,
            and_(
                user_roles.c.user_id == Competency.user_id,
                user_roles.c.role == UserRole.TUTOR.value,
            ),
        )
        .where(
            Competency.course_unit_id.in_(list(course_units)),
            # The caller cannot be a candidate for their own request.
            Competency.user_id != user.id,
        )
        .options(
            selectinload(Competency.user).selectinload(User.tutor_profile),
            selectinload(Competency.user).selectinload(User.university),
            selectinload(Competency.grade),
            selectinload(Competency.course_unit).selectinload(CourseUnit.university),
            selectinload(Competency.course_unit).selectinload(CourseUnit.subject),
        )
        # `id` breaks a tie `created_at` alone leaves open, because the dedup
        # below keeps the *first* row it sees for a tutor and that row has to be
        # the same one every time.
        .order_by(Competency.created_at.desc(), Competency.id.desc())
    )

    # The course unit's code rides alongside the candidate rather than inside it:
    # it is a tiebreak, and `MatchCandidate` is a wire type that has no business
    # carrying a field nothing but ordering reads.
    candidates: dict[uuid.UUID, tuple[MatchCandidate, str]] = {}
    exclusions: list[MatchExclusion] = []
    seen_exclusions: set[tuple[uuid.UUID, str]] = set()

    def exclude(tutor_id: uuid.UUID, reason: str) -> None:
        """Record why a tutor was ruled out, once per tutor and reason.

        A tutor with three competencies in the searched units is one row in the
        student's answer, not three copies of the same sentence.
        """
        key = (tutor_id, reason)
        if key not in seen_exclusions:
            seen_exclusions.add(key)
            exclusions.append(MatchExclusion(tutor_id=tutor_id, reason=reason))

    for competency in competencies.scalars():
        tutor = competency.user
        # An unverified grade is a claim rather than a fact, so it is reported
        # before anything is compared against it: `below_threshold` would tell a
        # tutor with an unchecked A that their problem was the number.
        if not competency.is_verified:
            exclude(tutor.public_id, "unverified")
            continue
        if tutor.university_id != user.university_id:
            exclude(tutor.public_id, "same_university_only")
            continue

        profile = tutor.tutor_profile
        if profile is not None and profile.standing is TutorStanding.SUSPENDED:
            exclude(tutor.public_id, "suspended")
            continue

        threshold = _grade_threshold(competency.course_unit)
        if competency.grade.grade_points < threshold:
            exclude(tutor.public_id, "below_threshold")
            continue

        if profile is None:
            # Verified grade, tutor role, and no profile: the standing a tutor
            # is ranked on does not exist, so there is nothing to propose. Named
            # rather than passed over, because the fix is on the tutor's side.
            exclude(tutor.public_id, "not_the_tutor")
            continue

        score = float(competency.grade.grade_points)
        if profile.average_rating is not None:
            score += float(profile.average_rating) / 10
        if profile.standing is TutorStanding.VERIFIED:
            score += 2.0
        elif profile.standing is TutorStanding.REDUCED:
            score -= 1.0

        candidate = MatchCandidate(
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

        entry = (candidate, competency.course_unit.code)
        current = candidates.get(candidate.tutor.user_id)
        if current is None or _candidate_rank_key(*entry) < _candidate_rank_key(
            *current
        ):
            candidates[candidate.tutor.user_id] = entry

    ranked = sorted(candidates.values(), key=lambda entry: _candidate_rank_key(*entry))
    return [candidate for candidate, _code in ranked], exclusions


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


def _grade_threshold(course_unit: CourseUnit) -> Decimal:
    scale = course_unit.university.grading_scale
    if scale is None:
        return Decimal("0")
    return scale.competency_min_points


async def load_help_request(
    db: AsyncSession,
    user: User,
    public_id: uuid.UUID,
) -> HelpRequest:
    """The caller's own help request, or a 404.

    Scoped to the caller rather than looked up bare, so one student cannot read
    another's topic by guessing an id, and so the answer to "not yours" and "not
    there" is the same one.
    """
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


def help_request_response(request: HelpRequest) -> HelpRequestResponse:
    """Render a help request as its response body.

    Hand-built from public ids rather than validated off the model, because the
    model exposes them through `*_public_id` properties that all have to be
    eager-loaded; stating the mapping here means one query shape covers it.
    """
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
