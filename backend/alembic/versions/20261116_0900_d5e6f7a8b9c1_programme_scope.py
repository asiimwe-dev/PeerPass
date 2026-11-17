"""scope course units and accounts to a programme

Revision ID: d5e6f7a8b9c1
Revises: c4d5e6f7a8b9

Programmes were already reference data; this is the revision that lets a course
unit and an account point at one. Within a faculty, programmes publish different
catalogues under different codes, so the faculty alone no longer says which
shelf a course belongs on.

Both columns are nullable, and each null has a meaning rather than being a gap:
a unit with no programme is one every programme in the faculty takes, and an
account with no programme predates the field or belongs to a faculty whose
programmes are not loaded. Both widen to the faculty instead of narrowing to
nothing, so an upgrade cannot lock anyone out of a catalogue.

The data is assigned by the seeder (`python -m app.db.seed`), not here: it is the
same catalogue either way, and a migration that hard-codes unit codes would be a
second copy of it.

`course_units.program_id` is RESTRICT because a programme with a catalogue must
not be deleted out from under its units; `users.program_id` is SET NULL because
an account outlives the programme it was enrolled in.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d5e6f7a8b9c1"
down_revision: str | None = "c4d5e6f7a8b9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "course_units",
        sa.Column("program_id", sa.Uuid(), nullable=True),
    )
    op.create_index(
        op.f("ix_course_units_program_id"),
        "course_units",
        ["program_id"],
        unique=False,
    )
    op.create_foreign_key(
        op.f("fk_course_units_program_id_programs"),
        "course_units",
        "programs",
        ["program_id"],
        ["id"],
        ondelete="RESTRICT",
    )

    op.add_column(
        "users",
        sa.Column("program_id", sa.Uuid(), nullable=True),
    )
    op.create_index(
        op.f("ix_users_program_id"),
        "users",
        ["program_id"],
        unique=False,
    )
    op.create_foreign_key(
        op.f("fk_users_program_id_programs"),
        "users",
        "programs",
        ["program_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("fk_users_program_id_programs"), "users", type_="foreignkey"
    )
    op.drop_index(op.f("ix_users_program_id"), table_name="users")
    op.drop_column("users", "program_id")

    op.drop_constraint(
        op.f("fk_course_units_program_id_programs"),
        "course_units",
        type_="foreignkey",
    )
    op.drop_index(op.f("ix_course_units_program_id"), table_name="course_units")
    op.drop_column("course_units", "program_id")
