"""add session messages

Revision ID: c4d5e6f7a8b9
Revises: b3c4d5e6f7a8

A session could be booked but not discussed. The two people who had just agreed
to meet had no way to say which library, which floor, or that they were outside,
so the last step of every booking happened off the app or not at all.

The table hangs off `sessions`, not off a conversation of its own. The session
already names the two parties and the topic, and those are the only two facts a
thread needs; a separate conversation row would duplicate both and drift.

`read_at` is a per-message timestamp rather than a per-reader table because a
session has exactly two parties: every message has one sender, so it has one
recipient, and there is no row to store twice.

The notification type this revision adds is a new value in an existing
`CHECK (type IN (...))` constraint. `native_enum=False` means the value lives in
the constraint rather than a type, so the constraint is replaced rather than
altered. The list is spelled in full because a check constraint is not additive.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c4d5e6f7a8b9"
down_revision: str | None = "b3c4d5e6f7a8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOTIFICATION_TYPES = (
    "request_received",
    "request_accepted",
    "request_declined",
    "session_started",
    "session_completed",
    "session_cancelled",
    "rating_received",
    "promotion",
    "message_received",
)

_NOTIFICATION_TYPES_BEFORE = tuple(
    value for value in _NOTIFICATION_TYPES if value != "message_received"
)


def _notification_type_check(values: Sequence[str]) -> str:
    joined = ", ".join(f"'{value}'" for value in values)
    return f"type IN ({joined})"


def upgrade() -> None:
    op.create_table(
        "session_messages",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("sender_id", sa.Uuid(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "length(body) > 0 AND length(body) <= 2000",
            name=op.f("ck_session_messages_body_length"),
        ),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["sessions.id"],
            name=op.f("fk_session_messages_session_id_sessions"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sender_id"],
            ["users.id"],
            name=op.f("fk_session_messages_sender_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_session_messages")),
    )
    op.create_index(
        op.f("ix_session_messages_public_id"),
        "session_messages",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        op.f("ix_session_messages_session_id"),
        "session_messages",
        ["session_id"],
    )
    op.create_index(
        op.f("ix_session_messages_sender_id"),
        "session_messages",
        ["sender_id"],
    )
    op.create_index(
        "ix_session_messages_session_created",
        "session_messages",
        ["session_id", "created_at"],
    )
    op.create_index(
        "ix_session_messages_session_unread",
        "session_messages",
        ["session_id", "read_at"],
    )

    op.drop_constraint(
        op.f("ck_notifications_notification_type"),
        "notifications",
        type_="check",
    )
    op.create_check_constraint(
        op.f("ck_notifications_notification_type"),
        "notifications",
        _notification_type_check(_NOTIFICATION_TYPES),
    )


def downgrade() -> None:
    # Rows of the removed type would stop the old constraint from being created,
    # so they go first. They are unread pointers to a thread whose table is about
    # to be dropped, and nothing else reads them.
    op.execute("DELETE FROM notifications WHERE type = 'message_received'")
    op.drop_constraint(
        op.f("ck_notifications_notification_type"),
        "notifications",
        type_="check",
    )
    op.create_check_constraint(
        op.f("ck_notifications_notification_type"),
        "notifications",
        _notification_type_check(_NOTIFICATION_TYPES_BEFORE),
    )

    op.drop_index(
        "ix_session_messages_session_unread", table_name="session_messages"
    )
    op.drop_index(
        "ix_session_messages_session_created", table_name="session_messages"
    )
    op.drop_index(
        op.f("ix_session_messages_sender_id"), table_name="session_messages"
    )
    op.drop_index(
        op.f("ix_session_messages_session_id"), table_name="session_messages"
    )
    op.drop_index(
        op.f("ix_session_messages_public_id"), table_name="session_messages"
    )
    op.drop_table("session_messages")
