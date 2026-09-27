"""Universities, subjects, and course units.

The curriculum a tutor is competent in and a student asks for help with. All
three are reference data loaded by an administrator rather than created by a
student, which is why none of them carries a user foreign key.
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import TimestampMixin, public_id_column

if TYPE_CHECKING:
    from app.models.competency import Competency
    from app.models.grading_scale import Grade, GradingScale


class University(Base, TimestampMixin):
    """A university students and tutors belong to."""

    __tablename__ = "universities"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    name: Mapped[str] = mapped_column(String(160), nullable=False, unique=True)

    #: Nullable because a student may register before choosing a faculty, and
    #: the tutor eligibility gate needs a scale to evaluate against. A tutor
    #: without one can hold the role but cannot be matched, which the matching
    #: service reports rather than guessing a scale.
    grading_scale_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("grading_scales.id", ondelete="RESTRICT"),
        nullable=True,
        index=True,
    )

    course_units: Mapped[list["CourseUnit"]] = relationship(back_populates="university")
    grading_scale: Mapped["GradingScale | None"] = relationship(
        back_populates="universities"
    )

    @property
    def grading_scale_public_id(self) -> uuid.UUID | None:
        """The scale's public id, for `UniversityResponse`.

        Reached through the relationship rather than off `grading_scale_id`, so
        the response cannot pick up the raw key by accident.
        """
        return self.grading_scale.public_id if self.grading_scale else None

    def __repr__(self) -> str:
        return f"<University {self.name}>"


class Subject(Base, TimestampMixin):
    """A department or faculty that course units are grouped under.

    Distinct from `CourseUnit`: a tutor is competent in a subject across several
    units, and grouping is what lets the matching engine widen a search when an
    exact unit has no eligible tutor.
    """

    __tablename__ = "subjects"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    name: Mapped[str] = mapped_column(String(160), nullable=False, unique=True)

    course_units: Mapped[list["CourseUnit"]] = relationship(back_populates="subject")

    def __repr__(self) -> str:
        return f"<Subject {self.name}>"


class CourseUnit(Base, TimestampMixin):
    """A single course unit, for example `MAT 221`.

    A help request names one specific unit, while a tutor's competency may cover
    several. Keeping them separate is what lets a student ask about one unit and
    a tutor prove competence in many.
    """

    __tablename__ = "course_units"
    #: Scoped to the university, not unique on its own. `MAT 221` at Makerere is
    #: a different course from `MAT 221` at Ndejje, is graded on that
    #: university's scale, and must be able to exist at the same time. A global
    #: unique index on `code` would forbid the second one and quietly push an
    #: administrator into inventing a suffix.
    __table_args__ = (
        UniqueConstraint(
            "university_id", "code", name="course_unit_code_per_university"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    #: The faculty's own unit code, which is what students search by.
    code: Mapped[str] = mapped_column(String(32), nullable=False, index=True)

    name: Mapped[str] = mapped_column(String(200), nullable=False)

    #: Free-text summary used to widen a match when an exact unit yields no
    #: eligible tutor. Advisory only: nothing is matched on it, because an
    #: unindexed text column cannot be matched on reliably.
    description: Mapped[str | None] = mapped_column(String(1000), nullable=True)

    subject_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("subjects.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    #: Required rather than optional, and that is what makes the per-university
    #: code constraint above sound: a composite unique index treats NULLs as
    #: distinct, so a nullable university would let two unscoped units share a
    #: code. It is also required for matching, which only pairs people at the
    #: same university and evaluates grades on that university's scale.
    university_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("universities.id", ondelete="RESTRICT"), nullable=False, index=True
    )

    #: The grade this unit awards. A unit sits on exactly one scale, inherited
    #: from its university's. Nullable because a unit can be catalogued before
    #: the university has a scale recorded.
    grade_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("grades.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    subject: Mapped["Subject | None"] = relationship(back_populates="course_units")
    university: Mapped["University"] = relationship(back_populates="course_units")
    grade: Mapped["Grade | None"] = relationship(back_populates="course_units")
    #: `passive_deletes` because the foreign key is already ON DELETE CASCADE,
    #: so the database will remove these without the ORM loading them first.
    competencies: Mapped[list["Competency"]] = relationship(
        back_populates="course_unit", passive_deletes=True
    )

    #: Public ids of referenced resources, for response schemas. See the note in
    #: `app.schemas.base` for why these exist rather than the raw key columns.

    @property
    def university_public_id(self) -> uuid.UUID:
        return self.university.public_id

    @property
    def subject_public_id(self) -> uuid.UUID | None:
        return self.subject.public_id if self.subject else None

    @property
    def grade_public_id(self) -> uuid.UUID | None:
        return self.grade.public_id if self.grade else None

    def __repr__(self) -> str:
        return f"<CourseUnit {self.code}>"
