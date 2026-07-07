"""finance completion: paid_by enum, expenses.paid_by, finance_transactions.accrual_to

Revision ID: 202607060002
Revises: 202607060001
Create Date: 2026-07-07 00:02:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = "202607060002"
down_revision: str | None = "202607060001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    paid_by_enum = postgresql.ENUM("INSTALLER", "OFFICE", name="paid_by", create_type=False)
    paid_by_enum.create(op.get_bind(), checkfirst=True)

    op.add_column(
        "expenses",
        sa.Column(
            "paid_by",
            paid_by_enum,
            nullable=False,
            server_default="INSTALLER",
        ),
    )
    op.add_column(
        "finance_transactions",
        sa.Column("accrual_to", paid_by_enum, nullable=True),
    )


def downgrade() -> None:
    op.drop_column("finance_transactions", "accrual_to")
    op.drop_column("expenses", "paid_by")

    paid_by_enum = postgresql.ENUM("INSTALLER", "OFFICE", name="paid_by", create_type=False)
    paid_by_enum.drop(op.get_bind(), checkfirst=True)
