"""Grading scales and the grades a course unit offers.

A grading scale is data, and it carries its own competency threshold. That is
the load-bearing decision in this module: the B+ rule is expressed as
`competency_min_points` on the scale rather than as a constant in the matching
engine, because the pilot's universities do not agree on what B+ means. A
four-point scale, a five-point scale, and a percentage scale each need a
different number, and hardcoding one of them would quietly mis-gate tutors at
every other institution.

Relationships are declared with string targets and no runtime imports, which
keeps the module free of a circular dependency: `University` points back here
for its scale, and here it points back for the universities using it.
"""

import uuid
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import TimestampMixin, public_id_column

if TYPE_CHECKING:
    # `University` lives in `course_unit`, not in a module of its own. Safe to
    # import under TYPE_CHECKING only: that module refers back to this one the
    # same way, so neither imports the other at runtime.
    from app.models.course_unit import CourseUnit, University


class GradingScale(Base, TimestampMixin):
    """A university's grading scale and the bar a tutor must clear on it."""

    __tablename__ = "grading_scales"

    __table_args__ = (
        CheckConstraint("max_points > 0", name="max_points_positive"),
        CheckConstraint(
            "competency_min_points > 0 AND competency_min_points <= max_points",
            name="competency_min_within_scale",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    name: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)

    #: The highest number of points a grade on this scale can carry.
    max_points: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False)

    #: The lowest grade that makes a tutor eligible, in this scale's points.
    #:
    #: Stored per scale rather than as a constant so the rule travels with the
    #: data. Changing the bar for one university must not change it for another.
    competency_min_points: Mapped[Decimal] = mapped_column(
        Numeric(6, 2), nullable=False
    )

    universities: Mapped[list["University"]] = relationship(
        back_populates="grading_scale"
    )
    grades: Mapped[list["Grade"]] = relationship(back_populates="grading_scale")

    def __repr__(self) -> str:
        return f"<GradingScale {self.name} max={self.max_points}>"


class Grade(Base, TimestampMixin):
    """A grade a course unit can award, with its value on the scale.

    A catalogue entry, not a student's result. A student's result is a
    `Competency`, which points at one of these and records whether the evidence
    was verified.
    """

    __tablename__ = "grades"

    __table_args__ = (
        CheckConstraint("grade_points > 0", name="grade_points_positive"),
        CheckConstraint("grade_points <= max_points", name="grade_points_within_max"),
        CheckConstraint("label <> ''", name="grade_label_not_blank"),
        # One label per scale. Without this a scale could offer both "B+" and
        # "B Plus" at different points values, and the matching engine would have
        # to guess which one a competency meant.
        UniqueConstraint("grading_scale_id", "label", name="grade_label_per_scale"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    label: Mapped[str] = mapped_column(String(16), nullable=False)

    #: The grade's value on its scale. Numeric, not a letter, because scales
    #: disagree on notation even where the underlying value agrees.
    grade_points: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False)

    grading_scale_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("grading_scales.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    #: Denormalised from the scale so the database can enforce
    #: `grade_points <= max_points`, which a CHECK constraint cannot do across
    #: tables.
    #:
    #: The cost of that denormalisation is drift: nothing stops a scale's
    #: `max_points` being edited underneath its grades, leaving them bounded by a
    #: maximum that no longer exists. Changing a published scale's maximum must
    #: therefore rescale its grades in the same transaction, which is an
    #: administrator operation and not yet written. Until it is, treat
    #: `max_points` here as write-once after the scale is seeded.
    max_points: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False)

    course_units: Mapped[list["CourseUnit"]] = relationship(back_populates="grade")
    grading_scale: Mapped["GradingScale"] = relationship(back_populates="grades")

    #: Public ids of referenced resources, for response schemas. See the note in
    #: `app.schemas.base` for why these exist rather than the raw key columns.

    @property
    def grading_scale_public_id(self) -> uuid.UUID:
        return self.grading_scale.public_id

    def __repr__(self) -> str:
        return f"<Grade {self.label} {self.grade_points}/{self.max_points}>"
