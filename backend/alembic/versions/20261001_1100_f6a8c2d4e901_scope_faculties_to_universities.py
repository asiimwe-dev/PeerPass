"""scope faculties and programs to their university.

Revision ID: f6a8c2d4e901
Revises: e9f2b3c4a1d8
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "f6a8c2d4e901"
down_revision: str | None = "e9f2b3c4a1d8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "subjects",
        sa.Column("description", sa.String(length=2000), nullable=True),
    )
    op.add_column("subjects", sa.Column("university_id", sa.Uuid(), nullable=True))
    op.create_index(
        op.f("ix_subjects_university_id"),
        "subjects",
        ["university_id"],
        unique=False,
    )
    op.create_foreign_key(
        op.f("fk_subjects_university_id_universities"),
        "subjects",
        "universities",
        ["university_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.drop_constraint(op.f("uq_subjects_name"), "subjects", type_="unique")
    op.create_unique_constraint(
        "faculty_name_per_university",
        "subjects",
        ["university_id", "name"],
    )

    op.create_table(
        "programs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("level", sa.String(length=32), nullable=False),
        sa.Column("description", sa.String(length=2000), nullable=True),
        sa.Column("university_id", sa.Uuid(), nullable=False),
        sa.Column("faculty_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["faculty_id"],
            ["subjects.id"],
            name=op.f("fk_programs_faculty_id_subjects"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["university_id"],
            ["universities.id"],
            name=op.f("fk_programs_university_id_universities"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_programs")),
        sa.UniqueConstraint(
            "university_id",
            "faculty_id",
            "name",
            name="program_name_per_faculty",
        ),
    )
    op.create_index(
        op.f("ix_programs_public_id"), "programs", ["public_id"], unique=True
    )
    op.create_index(
        op.f("ix_programs_university_id"), "programs", ["university_id"], unique=False
    )
    op.create_index(
        op.f("ix_programs_faculty_id"), "programs", ["faculty_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_programs_faculty_id"), table_name="programs")
    op.drop_index(op.f("ix_programs_university_id"), table_name="programs")
    op.drop_index(op.f("ix_programs_public_id"), table_name="programs")
    op.drop_table("programs")
    op.drop_constraint("faculty_name_per_university", "subjects", type_="unique")
    op.create_unique_constraint(op.f("uq_subjects_name"), "subjects", ["name"])
    op.drop_constraint(
        op.f("fk_subjects_university_id_universities"),
        "subjects",
        type_="foreignkey",
    )
    op.drop_index(op.f("ix_subjects_university_id"), table_name="subjects")
    op.drop_column("subjects", "university_id")
    op.drop_column("subjects", "description")
