"""add shared rate-limit counters for mobile authentication

Revision ID: 202610030023
Revises: 202610020022
Create Date: 2026-10-03
"""

from alembic import op
import sqlalchemy as sa


revision = "202610030023"
down_revision = "202610020022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "mobile_auth_rate_limits",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("key_hash", sa.String(length=64), nullable=False),
        sa.Column("action", sa.String(length=32), nullable=False),
        sa.Column("window_started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.UniqueConstraint("key_hash", "action", name="uq_mobile_auth_rate_limits_key_action"),
    )
    op.create_index(
        "ix_mobile_auth_rate_limits_window_started_at",
        "mobile_auth_rate_limits",
        ["window_started_at"],
    )


def downgrade() -> None:
    op.drop_table("mobile_auth_rate_limits")
