"""Users, the roles they hold, and refresh token handles.

Roles are a join table rather than a column. The pilot needs a tutor who is also
a student to be both, and a single `role_type` column would force one of those
to be false.
"""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
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
    from app.models.course_unit import University
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


class User(Base, TimestampMixin):
    """A person with an account.

    Academic records are not here. They live in `competencies`, which is what
    lets a future export or deletion drop academic data without touching
    identity.
    """

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    #: Stored lowercase. Lookups normalise before comparing, so that two
    #: addresses differing only in case cannot become two accounts.
    email: Mapped[str] = mapped_column(
        String(320), nullable=False, unique=True, index=True
    )

    full_name: Mapped[str] = mapped_column(String(160), nullable=False)

    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    #: Nullable because a student may register before choosing a faculty.
    university_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("universities.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    #: Set when a student accepts the academic-data consent. Competency
    #: submission is refused without it, which is the explicit consent the
    #: Uganda Data Protection and Privacy Act requires for academic records.
    academic_data_consented_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    university: Mapped["University | None"] = relationship()
    #: `foreign_keys` is required because `competencies` points at `users` twice
    #: -- the holder and the reviewer -- leaving the join otherwise ambiguous.
    competencies: Mapped[list["Competency"]] = relationship(
        back_populates="user",
        foreign_keys="Competency.user_id",
        passive_deletes=True,
    )
    tutor_profile: Mapped["TutorProfile | None"] = relationship(
        back_populates="user", uselist=False, passive_deletes=True
    )
    #: Revoked tokens are deleted rather than orphaned, so the ORM is told to
    #: let the cascade do it. `delete-orphan` alone would make the ORM unlink
    #: them one by one and issue the DELETEs itself.
    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        back_populates="user", passive_deletes=True
    )

    @property
    def university_public_id(self) -> uuid.UUID | None:
        """`None` when the user has not chosen a university yet."""
        return self.university.public_id if self.university else None

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

    user: Mapped["User"] = relationship(back_populates="refresh_tokens")
    replaced_by: Mapped["RefreshToken | None"] = relationship(
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
