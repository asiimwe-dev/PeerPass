"""merge migrations

Revision ID: 303b8552f492
Revises: f7a8b9c0d1e2, 0156d3079755
Create Date: 2026-11-05 23:15:58.180644

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = '303b8552f492'
down_revision: str | None = ('f7a8b9c0d1e2', '0156d3079755')
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
