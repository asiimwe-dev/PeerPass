"""let an account exist before it has a name, and add academic context

Revision ID: d05e672df7d5
Revises: c46b2a362a35
Create Date: 2026-09-29 13:53:16.442503

Three changes, all in service of the sign-up flow: a student now creates an
account with an email and a password only, and supplies a name, a faculty and a
year of study in an onboarding wizard immediately afterwards.

`full_name` becomes nullable so that a student who abandons the wizard still
holds a usable account. The alternative -- asking for the name on the sign-up
form, or inventing a placeholder a display name would later read out -- is a
worse version of the same trade.

`faculty_id` points at `subjects` rather than a dedicated faculties table.
`subjects` already groups course units, and the wizard needs exactly that
grouping to offer a student the units in their own faculty, so a second table
would hold the same names twice and the two would drift. The cost is that
`subjects.name` is globally unique, which stops a second university with a
"Faculty of Science" from being seeded. Acceptable while the pilot is a single
institution; the first thing to split when a second is added.

The `year_of_study` range check is written by hand. Autogenerate reported the
column and the index but not the table-level constraint, so without this line
the constraint would exist in the models and not in any database built from
these migrations -- which is exactly the class of drift `alembic check` is
supposed to catch and cannot catch on its own.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d05e672df7d5"
down_revision: str | None = "c46b2a362a35"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("year_of_study", sa.Integer(), nullable=True))
    op.add_column("users", sa.Column("faculty_id", sa.Uuid(), nullable=True))
    op.alter_column("users", "full_name", existing_type=sa.VARCHAR(160), nullable=True)
    op.create_index(op.f("ix_users_faculty_id"), "users", ["faculty_id"], unique=False)
    op.create_foreign_key(
        op.f("fk_users_faculty_id_subjects"),
        "users",
        "subjects",
        ["faculty_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_check_constraint(
        op.f("ck_users_year_of_study_in_range"),
        "users",
        "year_of_study IS NULL OR (year_of_study >= 1 AND year_of_study <= 6)",
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_users_year_of_study_in_range"), "users", type_="check")
    op.drop_constraint(op.f("fk_users_faculty_id_subjects"), "users", type_="foreignkey")
    op.drop_index(op.f("ix_users_faculty_id"), table_name="users")
    op.drop_column("users", "faculty_id")
    op.drop_column("users", "year_of_study")

    # Restoring NOT NULL last, and only on a database where every account has a
    # name. Any row created between this migration and its downgrade is a
    # name-less account, and this statement fails on the first of them rather
    # than inventing a value for it. Failing loudly is the intended outcome: a
    # downgrade that silently backfilled "Unknown" would put a fake name in front
    # of every account created while the wizard existed.
    op.alter_column("users", "full_name", existing_type=sa.VARCHAR(160), nullable=False)
