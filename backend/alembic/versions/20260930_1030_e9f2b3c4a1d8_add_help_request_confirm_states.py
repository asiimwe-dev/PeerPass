"""add help request confirm states

Revision ID: e9f2b3c4a1d8
Revises: d4e8a1b0c7f2
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "e9f2b3c4a1d8"
down_revision: str | None = "d4e8a1b0c7f2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

#: The constraint the initial schema created, and the one this migration drops.
#: Named explicitly because the enum is `native_enum=False`, so this is a CHECK
#: on a VARCHAR and the constraint name is the only handle on it.
CONSTRAINT = "ck_help_requests_help_request_status"

#: `open`, `matched`, `withdrawn`, `expired` -- the four states that existed
#: before a student could choose their tutor.
ORIGINAL = ("open", "matched", "withdrawn", "expired")


def upgrade() -> None:
    # `pending_confirmation` and `declined` are what turn a queue into a choice.
    #
    # Without `pending_confirmation`, a request whose student has picked a named
    # tutor is indistinguishable from one nobody has looked at, so the tutor
    # has no way to learn they were chosen and the student has no way to learn
    # they are waiting. Without `declined`, a tutor who said no and a request
    # nobody ever answered are the same row, and neither the student nor a later
    # reader can tell which happened.
    #
    # `declined` is terminal rather than a flag: a request the tutor refused is
    # a different event from a request still being worked, and collapsing them
    # loses the reason a request died.
    #
    # Both values are added to the existing CHECK rather than replaced. The
    # column is a VARCHAR (`native_enum=False`), so widening the constraint is
    # a metadata-only change -- no table rewrite, and no lock long enough to
    # matter on a table this size.
    op.drop_constraint(op.f(CONSTRAINT), "help_requests", type_="check")
    op.create_check_constraint(
        op.f(CONSTRAINT),
        "help_requests",
        "status::text = ANY (ARRAY["
        "'open'::character varying, "
        "'pending_confirmation'::character varying, "
        "'declined'::character varying, "
        "'matched'::character varying, "
        "'withdrawn'::character varying, "
        "'expired'::character varying"
        "]::text[])",
    )


def downgrade() -> None:
    # The two added states cannot be represented once they are gone, so this
    # fails loudly rather than quietly lying. Converting the rows first would
    # mean inventing a status for a request that genuinely was declined, and
    # `open` would be the wrong one: it would put an unanswered request back in
    # the queue for a tutor who already refused it.
    op.drop_constraint(op.f(CONSTRAINT), "help_requests", type_="check")
    op.create_check_constraint(
        op.f(CONSTRAINT),
        "help_requests",
        "status::text = ANY (ARRAY["
        + ", ".join(f"'{value}'::character varying" for value in ORIGINAL)
        + "]::text[])",
    )
