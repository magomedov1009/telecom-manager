"""add independent fiber and cable work logs

Revision ID: 202611190027
Revises: 202610050026
Create Date: 2026-11-19
"""

from alembic import op
import sqlalchemy as sa


revision = "202611190027"
down_revision = "202610050026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "fiber_work_logs",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("owner_user_id", sa.BigInteger(), nullable=False),
        sa.Column("object_name", sa.String(length=255), nullable=False),
        sa.Column("work_date", sa.Date(), nullable=False),
        sa.Column("cable_spans", sa.JSON(), nullable=False),
        sa.Column("splices", sa.JSON(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_fiber_work_logs_owner_user_id", "fiber_work_logs", ["owner_user_id"])
    op.create_index("ix_fiber_work_logs_work_date", "fiber_work_logs", ["work_date"])


def downgrade() -> None:
    op.drop_index("ix_fiber_work_logs_work_date", table_name="fiber_work_logs")
    op.drop_index("ix_fiber_work_logs_owner_user_id", table_name="fiber_work_logs")
    op.drop_table("fiber_work_logs")
