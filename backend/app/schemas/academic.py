"""Reference data a client needs to choose a course: scales, grades, subjects.

These are administrator-loaded lookups. They are read-only over the API, which is
why there are no create or update schemas here: a student cannot invent a course
unit their own transcript has never mentioned, and pretending otherwise would let
a user manufacture a match.
"""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import Field

from app.schemas.base import OrmSchema


class GradingScaleResponse(OrmSchema):
    """An institution's scale and the bar a tutor must clear on it.

    `competency_min_points` is sent to the client so the app can show a tutor
    their standing against the real threshold ("you need 3.5, you have 3.0")
    rather than a bare "not eligible". It reveals nothing sensitive: the bar is
    published in every institution's handbook.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    name: str
    max_points: Decimal = Field(max_digits=6, decimal_places=2)
    competency_min_points: Decimal = Field(max_digits=6, decimal_places=2)


class GradeResponse(OrmSchema):
    """One entry in a scale's grade catalogue."""

    id: uuid.UUID = Field(validation_alias="public_id")
    label: str
    grade_points: Decimal = Field(max_digits=6, decimal_places=2)
    max_points: Decimal = Field(max_digits=6, decimal_places=2)
    grading_scale_id: uuid.UUID = Field(validation_alias="grading_scale_public_id")


class SubjectResponse(OrmSchema):
    """A faculty or department grouping."""

    id: uuid.UUID = Field(validation_alias="public_id")
    name: str


class UniversityResponse(OrmSchema):
    """An institution.

    `grading_scale_id` is nullable because a student may register before choosing
    a faculty. A tutor cannot be matched until their university has a scale, and
    the matching service reports that rather than assuming one.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    name: str
    grading_scale_id: uuid.UUID | None = Field(
        default=None, validation_alias="grading_scale_public_id"
    )


class CourseUnitResponse(OrmSchema):
    """A course a student can ask for help with, or a tutor can prove competence.

    The `*_public_id` fields are the referenced resources' public ids, not their
    primary keys. `grading_scale_id` is reached through the university, so it is
    not on the unit itself and the field is absent by design.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    code: str
    name: str
    description: str | None = None
    university_id: uuid.UUID = Field(validation_alias="university_public_id")
    subject_id: uuid.UUID | None = Field(
        default=None, validation_alias="subject_public_id"
    )
    grade_id: uuid.UUID | None = Field(default=None, validation_alias="grade_public_id")
    created_at: datetime
