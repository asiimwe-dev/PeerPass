"""add admin role and audit events.

Revision ID: a7c9e1d4f602
Revises: f6a8c2d4e901
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a7c9e1d4f602"
down_revision: str | None = "f6a8c2d4e901"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint(
        op.f("ck_user_roles_user_role"), "user_roles", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_user_roles_user_role"),
        "user_roles",
        "role IN ('student', 'tutor', 'admin')",
    )
    op.create_table(
        "admin_audit_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=False),
        sa.Column("action", sa.String(length=80), nullable=False),
        sa.Column("target_type", sa.String(length=80), nullable=False),
        sa.Column("target_public_id", sa.Uuid(), nullable=True),
        sa.Column("context", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["actor_id"],
            ["users.id"],
            name=op.f("fk_admin_audit_events_actor_id_users"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_admin_audit_events")),
    )
    op.create_index(
        op.f("ix_admin_audit_events_public_id"),
        "admin_audit_events",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        op.f("ix_admin_audit_events_actor_id"),
        "admin_audit_events",
        ["actor_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_admin_audit_events_actor_id"), table_name="admin_audit_events"
    )
    op.drop_index(
        op.f("ix_admin_audit_events_public_id"), table_name="admin_audit_events"
    )
    op.drop_table("admin_audit_events")
    op.drop_constraint(
        op.f("ck_user_roles_user_role"), "user_roles", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_user_roles_user_role"),
        "user_roles",
        "role IN ('student', 'tutor')",
    )
