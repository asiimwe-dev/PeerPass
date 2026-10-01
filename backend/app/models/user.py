"""Users, the roles they hold, and refresh token handles.

Roles are a join table rather than a column. The pilot needs a tutor who is also
a student to be both, and a single `role_type` column would force one of those
to be false.
"""

from __future__ import annotations
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    Select,
    String,
    Table,
    UniqueConstraint,
    delete,
    insert,
    select,
)
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import (
    TimestampMixin,
    enum_column,
    public_id_column,
)
from app.models.enums import UserRole

if TYPE_CHECKING:
    from app.models.competency import Competency
    from app.models.course_unit import Subject, University
    from app.models.tutor_profile import TutorProfile


#: Many-to-many between users and roles.
#:
#: A table rather than an association object because the pair carries no data of
#: its own. `primary_key` on both columns is the whole constraint: it makes
#: holding a role twice impossible, so the uniqueness rule is the schema rather
#: than a check a service has to remember to run.
user_roles = Table(
    "user_roles",
    Base.metadata,
    Column("user_id", ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("role", enum_column(UserRole, name="user_role"), primary_key=True),
)

user_primary_course_units = Table(
    "user_primary_course_units",
    Base.metadata,
    Column("user_id", ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column(
        "course_unit_id",
        ForeignKey("course_units.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)

#: What a deleted account is called wherever somebody else is being named.
#:
#: A fixed string rather than the scrubbed row, for two reasons. A tombstone has
#: `full_name = None` and an email rewritten to a synthetic
#: `deleted+...@deleted.invalid`, so the old `full_name or email` fallback would
#: render either a blank or an internal placeholder as a person's name. And
#: "Deleted user" says something about the person, where the placeholder says
#: something about this database.
DELETED_USER_DISPLAY_NAME = "Deleted user"


class User(Base, TimestampMixin):
    """A person with an account.

    Academic records are not here. They live in `competencies`, which is what
    lets a future export or deletion drop academic data without touching
    identity.
    """

    __tablename__ = "users"
    __table_args__ = (
        # A year of study outside 1-6 is a typo, not a student's year, and it
        # would silently produce an empty cohort filter. The upper bound is 6
        # because that is the longest a Ugandan undergraduate degree runs in
        # practice; raise it here if that stops being true.
        CheckConstraint(
            "year_of_study IS NULL OR (year_of_study >= 1 AND year_of_study <= 6)",
            name="year_of_study_in_range",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    #: Stored lowercase. Lookups normalise before comparing, so that two
    #: addresses differing only in case cannot become two accounts.
    email: Mapped[str] = mapped_column(
        String(320), nullable=False, unique=True, index=True
    )

    #: Nullable, and that is a deliberate product decision rather than an
    #: oversight. Sign-up asks for an email and a password only; the name is
    #: collected in the first step of the onboarding wizard, which is a
    #: separate screen the student can abandon. Making the column NOT NULL
    #: would mean either asking for the name on a form we have decided to keep
    #: minimal, or inventing a placeholder that a display name would later read
    #: out. An account with no name is a real, reachable state, and the client
    #: derives a fallback greeting from it.
    full_name: Mapped[str | None] = mapped_column(String(160), nullable=True)

    #: Year of study, collected in the wizard's academic step. Nullable because
    #: the wizard can be abandoned partway, and because a tutor's own year is not
    #: the interesting thing about them. Not used by matching.
    year_of_study: Mapped[int | None] = mapped_column(Integer, nullable=True)

    #: The faculty the student belongs to.
    #:
    #: This points at `subjects` rather than a dedicated faculties table, and
    #: the reason is load-bearing rather than lazy: `subjects` already groups
    #: course units, and the wizard needs exactly that grouping to offer a
    #: student the course units in their own faculty. A second table would hold
    #: the same names twice and the two would drift.
    #:
    #: The cost is `subjects.name` being globally unique, so two universities
    #: with a "Faculty of Science" cannot both be seeded. That is acceptable
    #: while the pilot is a single institution, and it is the first thing to
    #: split when a second one is added.
    faculty_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("subjects.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    #: Nullable because a student may register before choosing a faculty.
    university_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("universities.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    #: When the account holder asked for their account to be erased, or `None`
    #: for an account that has never asked.
    #:
    #: A timestamp rather than an `is_deleted` boolean, because the fact worth
    #: keeping is *when*, not merely that it happened: a data-retention claim
    #: has to be able to say the request was received on a given date. Two
    #: columns that both mean "gone" cannot disagree, whereas a boolean and a
    #: timestamp can.
    #:
    #: The row itself is never deleted. Every FK to `users.id` is `CASCADE`, so
    #: removing the row would take the sessions, ratings, endorsements and
    #: competencies with it -- and session records are the source of truth for
    #: a tutor's hours, so erasing them would silently rewrite a colleague's
    #: certificate progress. Instead deletion scrubs the identifying columns and
    #: leaves the evidence, which is what "anonymised" has to mean if the
    #: evidence is worth keeping at all.
    #:
    #: Everything that grants access must treat a non-null value as
    #: unauthenticated. Otherwise this is a live account with a blank name.
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    @property
    def is_deleted(self) -> bool:
        """Whether this row is a tombstone rather than a usable account."""
        return self.deleted_at is not None

    @property
    def display_name(self) -> str:
        """The name to show where somebody else is being named.

        One definition, because there are three student-facing surfaces that
        label a person and a fourth copy of this fallback is a fourth place for
        it to be wrong.
        """
        if self.is_deleted:
            return DELETED_USER_DISPLAY_NAME
        return self.full_name or self.email

    #: Set when a student accepts the academic-data consent. Competency
    #: submission is refused without it, which is the explicit consent the
    #: Uganda Data Protection and Privacy Act requires for academic records.
    academic_data_consented_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    university: Mapped[University | None] = relationship()
    faculty: Mapped[Subject | None] = relationship()
    #: `foreign_keys` is required because `competencies` points at `users` twice
    #: -- the holder and the reviewer -- leaving the join otherwise ambiguous.
    competencies: Mapped[list[Competency]] = relationship(
        back_populates="user",
        foreign_keys="Competency.user_id",
        passive_deletes=True,
    )
    tutor_profile: Mapped[TutorProfile | None] = relationship(
        back_populates="user", uselist=False, passive_deletes=True
    )
    #: Revoked tokens are deleted rather than orphaned, so the ORM is told to
    #: let the cascade do it. `delete-orphan` alone would make the ORM unlink
    #: them one by one and issue the DELETEs itself.
    refresh_tokens: Mapped[list[RefreshToken]] = relationship(
        back_populates="user", passive_deletes=True
    )

    @property
    def university_public_id(self) -> uuid.UUID | None:
        """`None` when the user has not chosen a university yet."""
        return self.university.public_id if self.university else None

    @property
    def faculty_public_id(self) -> uuid.UUID | None:
        """`None` when the user has not chosen a faculty yet.

        Read through the relationship for the same reason as
        `university_public_id`: a response schema must not be able to pick up
        the raw key column by accident.
        """
        return self.faculty.public_id if self.faculty else None

    def __repr__(self) -> str:
        return f"<User {self.email}>"


class RefreshToken(Base):
    """A single issued refresh token, tracked so it can be revoked.

    Only a hash of the token is stored. A stolen database therefore hands an
    attacker no usable refresh token, and the `jti` claim inside the token
    identifies the row without the row storing anything secret.

    Rotation per RFC 9700: presenting a token revokes it and issues a
    replacement. Presenting one that was already revoked is treated as theft --
    the whole family is revoked, because either the attacker or the real user
    is holding a token that should have died, and there is no way to tell which.
    """

    __tablename__ = "refresh_tokens"
    __table_args__ = (
        UniqueConstraint("user_id", "token_hash", name="refresh_token_hash"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, index=True)

    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    #: The row that replaced this one, so a reuse can revoke the whole chain.
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL"), nullable=True
    )

    user: Mapped[User] = relationship(back_populates="refresh_tokens")
    replaced_by: Mapped[RefreshToken | None] = relationship(
        remote_side="RefreshToken.id"
    )

    @property
    def is_revoked(self) -> bool:
        return self.revoked_at is not None

    def __repr__(self) -> str:
        return f"<RefreshToken user={self.user_id} revoked={self.is_revoked}>"


# Roles are read and written through these two functions rather than through an
# ORM relationship. `UserRole` is an enum, and SQLAlchemy cannot use an enum as
# a relationship target, so `secondary=user_roles` would raise at mapper
# configuration. A pair of explicit queries is cheaper to reason about than a
# workaround, and it makes the extra round trip visible instead of surprising.


def select_roles(user_id: uuid.UUID) -> Select[tuple[str]]:
    """Every role a user holds."""
    return select(user_roles.c.role).where(user_roles.c.user_id == user_id)


async def load_roles(db: AsyncSession, user_id: uuid.UUID) -> set[UserRole]:
    """The user's roles as a set, empty when they hold none."""
    result = await db.execute(select_roles(user_id))
    return {UserRole(value) for value in result.scalars()}


async def set_roles(db: AsyncSession, user_id: uuid.UUID, roles: set[UserRole]) -> None:
    """Replace a user's roles outright.

    Delete-then-insert rather than a diff. The table holds at most a couple of
    rows per user, so the diff would cost more to get right than it saves.
    """
    await db.execute(delete(user_roles).where(user_roles.c.user_id == user_id))
    if roles:
        await db.execute(
            insert(user_roles),
            [{"user_id": user_id, "role": role.value} for role in roles],
        )


def has_role(roles: set[UserRole], role: UserRole) -> bool:
    """Whether a loaded role set contains `role`."""
    return role in roles


def select_primary_course_unit_public_ids(
    user_id: uuid.UUID,
) -> Select[tuple[uuid.UUID]]:
    """Every primary course unit public ID a user holds."""
    from app.models.course_unit import CourseUnit

    return (
        select(CourseUnit.public_id)
        .join(
            user_primary_course_units,
            CourseUnit.id == user_primary_course_units.c.course_unit_id,
        )
        .where(user_primary_course_units.c.user_id == user_id)
    )


async def load_primary_course_unit_public_ids(
    db: AsyncSession, user_id: uuid.UUID
) -> list[uuid.UUID]:
    """The user's primary course units public IDs as a list."""
    result = await db.execute(select_primary_course_unit_public_ids(user_id))
    return list(result.scalars())


async def set_primary_course_units(
    db: AsyncSession, user_id: uuid.UUID, course_unit_ids: list[uuid.UUID]
) -> None:
    """Replace a user's primary course units outright."""
    await db.execute(
        delete(user_primary_course_units).where(
            user_primary_course_units.c.user_id == user_id
        )
    )
    if course_unit_ids:
        await db.execute(
            insert(user_primary_course_units),
            [{"user_id": user_id, "course_unit_id": uid} for uid in course_unit_ids],
        )
