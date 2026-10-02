"""additional works refactor: remove client/title/expenses, work_type_id NOT NULL

Revision ID: 202607060003
Revises: 202607060002
Create Date: 2026-07-08 00:03:00
"""

from collections.abc import Sequence

revision: str = "202607060003"
down_revision: str | None = "202607060002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Keep legacy client/connection columns until 202607060005 has copied
    # provider information from clients. Migration 202607060007 removes these
    # fields after that data migration. work_type_id is also added later.
    pass


def downgrade() -> None:
    pass
