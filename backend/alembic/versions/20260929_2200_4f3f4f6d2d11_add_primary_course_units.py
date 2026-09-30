"""store the course units selected during onboarding

Revision ID: 4f3f4f6d2d11
Revises: d05e672df7d5
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "4f3f4f6d2d11"
down_revision: str | None = "d05e672df7d5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_primary_course_units",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("course_unit_id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["course_unit_id"],
            ["course_units.id"],
            name=op.f("fk_user_primary_course_units_course_unit_id_course_units"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_user_primary_course_units_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id", "course_unit_id"),
    )


def downgrade() -> None:
    op.drop_table("user_primary_course_units")
