"""Shared column types and mixins.

The identifier convention is the important part of this module:

- The primary key is a UUIDv7. It is also the write-order index, and a
  time-ordered value inserts at the end of the B-tree rather than scattering
  inserts across it. `sessions` grows fastest and is read newest-first, so this
  is where it pays.
- A separate `public_id` UUIDv4 is what clients ever see. It is random on
  purpose: a public id that encoded its creation time would let one leaked link
  be used to date and enumerate every other record.

Clients therefore never see, and cannot guess, a row's primary key.
"""

import enum
import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Enum, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.core.security import new_public_id

# Explicit naming so a renamed constraint is applied by Alembic as a rename
# rather than a drop-and-recreate, which would drop the data with it.
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


def public_id_column() -> Mapped[uuid.UUID]:
    """The client-facing identifier.

    A function rather than a shared `mapped_column` instance, so each model gets
    its own column object. Reusing one column object across tables is a
    well-known source of hard-to-trace SQLAlchemy errors.
    """
    return mapped_column(
        Uuid(as_uuid=True),
        default=new_public_id,
        unique=True,
        nullable=False,
        index=True,
    )


def _utcnow() -> datetime:
    return datetime.now(UTC)


def enum_column(enum_type: type[enum.Enum], *, name: str) -> Enum:
    """A VARCHAR column storing an enum's *value*.

    Two deliberate choices:

    - `values_callable` makes SQLAlchemy persist `tutor` rather than `TUTOR`.
      Without it the database holds the Python identifier, so renaming a member
      silently rewrites stored data and the column stops matching the wire
      format the client already parses.
    - `native_enum=False` stores a VARCHAR with a CHECK constraint instead of a
      PostgreSQL enum type. A native enum cannot be given a new value without a
      migration that rewrites the type, which is a poor trade for a column that
      will grow a handful of states.
    """
    return Enum(
        enum_type,
        name=name,
        native_enum=False,
        values_callable=lambda members: [member.value for member in members],
        validate_strings=True,
        length=32,
    )


class TimestampMixin:
    """Creation and modification times, both stored in UTC.

    Defaults are applied in Python rather than by the database so that a test
    can assert on a value it controls, and so the behaviour does not differ
    between SQLite and PostgreSQL.
    """

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=_utcnow,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=_utcnow,
        onupdate=_utcnow,
    )


__all__ = ["NAMING_CONVENTION", "TimestampMixin", "enum_column", "public_id_column"]
