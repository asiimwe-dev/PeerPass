"""add the session handshake columns

Revision ID: b7e1c9a4d2f8
Revises: 4f3f4f6d2d11
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b7e1c9a4d2f8"
down_revision: str | None = "4f3f4f6d2d11"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "sessions",
        sa.Column("session_pin", sa.String(length=2), nullable=True),
    )
    op.add_column(
        "sessions",
        sa.Column("meeting_link", sa.String(length=500), nullable=True),
    )
    # The pin is a two-digit value the platform owns. The column length alone
    # would accept any two characters, so the check is what makes the value a
    # pin rather than arbitrary text. It is deliberately nullable: a pin exists
    # only from the moment a tutor is matched, and a session row created before
    # that has none.
    op.create_check_constraint(
        op.f("ck_sessions_session_pin_length"),
        "sessions",
        "session_pin IS NULL OR length(session_pin) = 2",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_sessions_session_pin_length"),
        "sessions",
        type_="check",
    )
    op.drop_column("sessions", "meeting_link")
    op.drop_column("sessions", "session_pin")
