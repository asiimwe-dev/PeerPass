"""Tutor competencies: a user's grade in a course unit, and whether it is verified.

This is the academic record, and it is the table the whole matching gate turns
on. Two decisions are load-bearing.

The gate threshold is read from the course unit's grading scale, not hardcoded.
"B+ or higher" means different numbers on a four-point, a five-point, and a
percentage scale, so the rule travels with the data.

Verification is per competency, not per user. A transcript may confirm one unit
and say nothing about another, and a tutor is expected to be selectively
competent rather than uniformly so.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import (
    TimestampMixin,
    enum_column,
    public_id_column,
)
from app.models.enums import CompetencyStatus, VerificationSource

if TYPE_CHECKING:
    from app.models.course_unit import CourseUnit
    from app.models.grading_scale import Grade
    from app.models.user import User


class Competency(Base, TimestampMixin):
    """One verified or pending grade, in one course unit, held by one user."""

    __tablename__ = "competencies"
    __table_args__ = (
        # A user has at most one record per unit. Stated as a schema constraint
        # so a second submission is rejected by the database rather than by a
        # check some code path might forget.
        UniqueConstraint("user_id", "course_unit_id", name="competency_user_unit"),
        CheckConstraint(
            "verified_at IS NULL OR status = 'verified'",
            name="verified_requires_status",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    course_unit_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("course_units.id", ondelete="CASCADE"), nullable=False, index=True
    )

    grade_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("grades.id", ondelete="RESTRICT"), nullable=False, index=True
    )

    status: Mapped[CompetencyStatus] = mapped_column(
        enum_column(CompetencyStatus, name="competency_status"),
        nullable=False,
        default=CompetencyStatus.PENDING,
    )

    source: Mapped[VerificationSource] = mapped_column(
        enum_column(VerificationSource, name="verification_source"),
        nullable=False,
    )

    #: Who reviewed it, for an override submitted by a faculty member.
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    #: Why a submission was rejected. Shown to the tutor so a rejection is
    #: actionable rather than just refused.
    rejection_reason: Mapped[str | None] = mapped_column(String(500), nullable=True)

    #: Where the evidence lives, for example an object-store key. A reference,
    #: not the document: academic records must not be inlined into a row that
    #: gets selected by a list query.
    evidence_reference: Mapped[str | None] = mapped_column(String(500), nullable=True)

    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    #: `foreign_keys` is required, not decorative: this table has two foreign
    #: keys to `users` -- the holder and the reviewer -- so without it SQLAlchemy
    #: cannot tell which one the relationship follows.
    user: Mapped[User] = relationship(
        back_populates="competencies",
        foreign_keys=[user_id],
        passive_deletes=True,
    )
    course_unit: Mapped[CourseUnit] = relationship(
        back_populates="competencies", passive_deletes=True
    )
    grade: Mapped[Grade] = relationship()
    reviewed_by: Mapped[User | None] = relationship(foreign_keys=[reviewed_by_id])

    @property
    def is_verified(self) -> bool:
        return self.status is CompetencyStatus.VERIFIED

    def meets_threshold(self, minimum_points: object) -> bool:
        """Whether this competency clears a scale's competency bar.

        Takes the threshold as an argument rather than reading the scale itself.
        The caller already has the scale loaded, and passing it in keeps this
        method a total function that a test can exercise without a database.

        An unverified competency never meets the bar, whatever its grade. That
        is the whole point of the tier-1 gate: the grade is a claim until
        someone has checked it.
        """
        if not self.is_verified:
            return False
        return self.grade.grade_points >= minimum_points  # type: ignore[operator]

    #: Public ids of the resources this row references.
    #:
    #: A response schema that declared `course_unit_id` without an alias would
    #: have `from_attributes` hand it the internal primary key, which looks
    #: plausible in a test and leaks the key in production. These exist so the
    #: public id is what the field can only ever receive.
    #:
    #: They read a relationship, so the service must eager-load it. On an async
    #: session a lazy load raises `MissingGreenlet` rather than quietly costing a
    #: query, which is the behaviour wanted here: a missing `selectinload` should
    #: be a crash, not an N+1 that only shows up under load.

    @property
    def user_public_id(self) -> uuid.UUID:
        return self.user.public_id

    @property
    def course_unit_public_id(self) -> uuid.UUID:
        return self.course_unit.public_id

    @property
    def grade_public_id(self) -> uuid.UUID:
        return self.grade.public_id

    def __repr__(self) -> str:
        return (
            f"<Competency user={self.user_id} unit={self.course_unit_id} {self.status}>"
        )
