"""add website entity mapping to mobile sync records

Revision ID: 202607300015
Revises: 202607260014
"""

from alembic import op
import sqlalchemy as sa


revision = "202607300015"
down_revision = "202607260014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "mobile_sync_records",
        sa.Column("site_id", sa.BigInteger(), nullable=True),
    )
    op.create_index(
        "ix_mobile_sync_records_site_id",
        "mobile_sync_records",
        ["site_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_mobile_sync_records_site_id",
        table_name="mobile_sync_records",
    )
    op.drop_column("mobile_sync_records", "site_id")
