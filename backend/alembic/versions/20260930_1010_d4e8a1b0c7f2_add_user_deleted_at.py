"""add user deleted_at

Revision ID: d4e8a1b0c7f2
Revises: a3f7c2e91b04
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d4e8a1b0c7f2"
down_revision: str | None = "a3f7c2e91b04"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # One nullable timestamptz column, and no `is_deleted` boolean beside it.
    # The timestamp is the fact worth keeping -- a data-retention claim has to
    # be able to say the request arrived on a given date -- and a second column
    # meaning the same thing is a second thing that can disagree with the first.
    #
    # The row is not deleted by this migration, and nothing here loosens the
    # cascading FKs pointing at `users.id`. That is the point. Sessions are the
    # source of truth for a tutor's hours, so removing a user row would erase a
    # colleague's certificate progress as a side effect of one person asking to
    # be forgotten. Deletion scrubs the identifying columns and leaves the
    # evidence, which is the only reading of "anonymised" that keeps the hours.
    #
    # Timezone-aware because the record answers "when did they ask", and a naive
    # timestamp read back in a different offset would answer a different
    # question.
    op.add_column(
        "users",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Indexed because it is on the authentication path: every token check has to
    # ask whether the account is a tombstone, and that runs on every request
    # rather than on a rare admin query.
    op.create_index(
        op.f("ix_users_deleted_at"),
        "users",
        ["deleted_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_users_deleted_at"), table_name="users")
    # Restores the pre-deletion schema, which is to say it discards the record of
    # who asked. The scrubbed PII stays scrubbed; only the audit trail is lost,
    # which is why this is a downgrade and not something to run in anger.
    op.drop_column("users", "deleted_at")
