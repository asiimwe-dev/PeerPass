"""Read-only reference data the onboarding wizard needs to populate its pickers.

No create, update, or delete. Universities, faculties, and course units are
administrator-loaded, and a student who could invent a course unit their own
transcript never mentioned could manufacture a match for it.
"""

import uuid

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import DatabaseSession
from app.models.course_unit import CourseUnit, Subject, University
from app.schemas.academic import CourseUnitResponse, SubjectResponse, UniversityResponse

router = APIRouter(prefix="/academics", tags=["academics"])


@router.get(
    "/universities",
    response_model=list[UniversityResponse],
    summary="List institutions",
)
async def list_universities(db: DatabaseSession) -> list[UniversityResponse]:
    """Every institution, alphabetically.

    Unauthenticated on purpose. The sign-up form shows the student where they
    study before they have an account, and the data is public: a published
    faculty list leaks nothing a prospectus does not.
    """
    result = await db.execute(
        select(University)
        .options(selectinload(University.grading_scale))
        .order_by(University.name)
    )
    return [UniversityResponse.model_validate(row) for row in result.scalars()]


@router.get(
    "/faculties",
    response_model=list[SubjectResponse],
    summary="List faculties and departments",
)
async def list_faculties(db: DatabaseSession) -> list[SubjectResponse]:
    """Every faculty, alphabetically.

    Not filtered by university, and that is a consequence of pointing
    `users.faculty_id` at `subjects`: a faculty is a property of a course unit,
    not of an institution, so the list is global while the pilot is a single
    institution. When a second university is seeded this becomes a per-university
    query and `subjects` needs a `university_id` of its own.
    """
    result = await db.execute(select(Subject).order_by(Subject.name))
    return [SubjectResponse.model_validate(row) for row in result.scalars()]


@router.get(
    "/course-units",
    response_model=list[CourseUnitResponse],
    summary="List course units",
)
async def list_course_units(
    db: DatabaseSession,
    subject_id: uuid.UUID | None = None,
) -> list[CourseUnitResponse]:
    """Course units, optionally narrowed to one faculty.

    The filter is the wizard's third step: a student who has named their faculty
    is offered the units belonging to it. The query parameter is the faculty's
    *public* id, like every other identifier the client handles, and a malformed
    one is a 422 from FastAPI rather than a silently empty list.

    Ordered by code, because a student scanning for `BIT 221` is looking for a
    code, not for alphabetical position.
    """
    query = select(CourseUnit).options(
        selectinload(CourseUnit.university),
        selectinload(CourseUnit.subject),
        selectinload(CourseUnit.grade),
    )
    if subject_id is not None:
        subject_uuid = await _subject_uuid(db, subject_id)
        if subject_uuid is None:
            return []
        query = query.where(CourseUnit.subject_id == subject_uuid)

    result = await db.execute(query.order_by(CourseUnit.university_id, CourseUnit.code))
    return [CourseUnitResponse.model_validate(row) for row in result.scalars()]


async def _subject_uuid(db: AsyncSession, public_id: uuid.UUID) -> uuid.UUID | None:
    """The primary key for a faculty public id, or `None`.

    An unrecognised filter returns an empty list rather than a 404. The client
    filtered on a value it believes exists, so the honest answer to "units in
    this faculty" is "none" -- a 404 would put the wizard into an error state for
    something the student did not do.
    """
    result = await db.execute(select(Subject.id).where(Subject.public_id == public_id))
    return result.scalar_one_or_none()
