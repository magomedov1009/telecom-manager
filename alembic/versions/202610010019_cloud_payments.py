"""add cloud payment orders

Revision ID: 202610010019
Revises: 202610010018
Create Date: 2026-10-01
"""

import sqlalchemy as sa
from alembic import op


revision = "202610010019"
down_revision = "202610010018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "cloud_payments",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("organization_id", sa.BigInteger(), nullable=False),
        sa.Column("public_token", sa.String(length=96), nullable=False),
        sa.Column("label", sa.String(length=64), nullable=False),
        sa.Column("plan_code", sa.String(length=32), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="pending"),
        sa.Column("provider_operation_id", sa.String(length=255), nullable=True),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["organization_id"], ["mobile_organizations.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("public_token"),
        sa.UniqueConstraint("label"),
        sa.UniqueConstraint("provider_operation_id"),
    )
    op.create_index("ix_cloud_payments_organization_id", "cloud_payments", ["organization_id"])
    op.create_index("ix_cloud_payments_public_token", "cloud_payments", ["public_token"])
    op.create_index("ix_cloud_payments_label", "cloud_payments", ["label"])


def downgrade() -> None:
    op.drop_table("cloud_payments")
