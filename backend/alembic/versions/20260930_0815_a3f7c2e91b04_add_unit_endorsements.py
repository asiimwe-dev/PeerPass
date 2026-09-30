"""add unit endorsements

Revision ID: a3f7c2e91b04
Revises: b7e1c9a4d2f8
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a3f7c2e91b04"
down_revision: str | None = "b7e1c9a4d2f8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Its own table rather than columns on `ratings`. A rating says how a tutor
    # was; an endorsement says what they covered. Putting the second on the first
    # would give the rating table a course unit column that is meaningless for
    # the many sessions nobody endorses, and would make the standing rules read a
    # score that no longer means only what its name says.
    op.create_table(
        "unit_endorsements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("rater_id", sa.Uuid(), nullable=False),
        sa.Column("ratee_id", sa.Uuid(), nullable=False),
        sa.Column("course_unit_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        # A self-endorsement is a claim about someone vouching for themselves,
        # which is either a bug or an attempt to inflate the count matching will
        # read, and neither should need a service to be trusted to refuse it.
        sa.CheckConstraint(
            "rater_id <> ratee_id",
            name=op.f("ck_unit_endorsements_endorsement_parties_differ"),
        ),
        # `RESTRICT` on the course unit, unlike the cascading references beside
        # it: a unit is reference data a transcript points at, and an endorsement
        # that blocked its retirement over one mention would make it impossible
        # to retire at all.
        sa.ForeignKeyConstraint(
            ["course_unit_id"],
            ["course_units.id"],
            name=op.f("fk_unit_endorsements_course_unit_id_course_units"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["ratee_id"],
            ["users.id"],
            name=op.f("fk_unit_endorsements_ratee_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["rater_id"],
            ["users.id"],
            name=op.f("fk_unit_endorsements_rater_id_users"),
            ondelete="CASCADE",
        ),
        # Cascades: the claim is about something that happened, so if the session
        # row goes there is nothing left for the endorsement to refer to, and
        # keeping it would leave a count no session backs.
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["sessions.id"],
            name=op.f("fk_unit_endorsements_session_id_sessions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_unit_endorsements")),
        # One claim per rater per unit per session, so a corrected re-submission
        # replaces its row instead of adding a second one the aggregate would
        # count twice.
        sa.UniqueConstraint(
            "session_id",
            "rater_id",
            "course_unit_id",
            name="endorsement_per_rater_unit",
        ),
    )
    op.create_index(
        op.f("ix_unit_endorsements_public_id"),
        "unit_endorsements",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        op.f("ix_unit_endorsements_course_unit_id"),
        "unit_endorsements",
        ["course_unit_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_unit_endorsements_ratee_id"),
        "unit_endorsements",
        ["ratee_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_unit_endorsements_rater_id"),
        "unit_endorsements",
        ["rater_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_unit_endorsements_session_id"),
        "unit_endorsements",
        ["session_id"],
        unique=False,
    )


def downgrade() -> None:
    # `drop_table` takes the indexes and constraints with it. They are named
    # rather than left to the cascade so a future migration can refer to them,
    # which is the same reason the initial schema names everything.
    op.drop_index(
        op.f("ix_unit_endorsements_session_id"), table_name="unit_endorsements"
    )
    op.drop_index(
        op.f("ix_unit_endorsements_rater_id"), table_name="unit_endorsements"
    )
    op.drop_index(
        op.f("ix_unit_endorsements_ratee_id"), table_name="unit_endorsements"
    )
    op.drop_index(
        op.f("ix_unit_endorsements_course_unit_id"), table_name="unit_endorsements"
    )
    op.drop_index(
        op.f("ix_unit_endorsements_public_id"), table_name="unit_endorsements"
    )
    op.drop_table("unit_endorsements")