"""record the payment provider for each cloud checkout

Revision ID: 202610050026
Revises: 202610040025
Create Date: 2026-10-02
"""

from alembic import op
import sqlalchemy as sa


revision = "202610050026"
down_revision = "202610040025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "cloud_payments",
        sa.Column(
            "provider",
            sa.String(length=32),
            nullable=False,
            server_default="yoomoney",
        ),
    )


def downgrade() -> None:
    op.drop_column("cloud_payments", "provider")
