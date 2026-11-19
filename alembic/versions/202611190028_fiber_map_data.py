"""store offline map background and schematic points in fiber log

Revision ID: 202611190028
Revises: 202611190027
Create Date: 2026-11-19
"""

from alembic import op
import sqlalchemy as sa


revision = "202611190028"
down_revision = "202611190027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("fiber_work_logs", sa.Column("map_data", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("fiber_work_logs", "map_data")
