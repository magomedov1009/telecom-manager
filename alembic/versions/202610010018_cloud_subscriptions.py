"""add cloud subscription foundation

Revision ID: 202610010018
Revises: 202609160017
Create Date: 2026-10-01
"""

import sqlalchemy as sa
from alembic import op


revision = "202610010018"
down_revision = "202609160017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "mobile_organizations",
        sa.Column("hosting_mode", sa.String(length=32), nullable=False, server_default="cloud"),
    )
    op.add_column(
        "mobile_organizations",
        sa.Column("is_legacy_workspace", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    # The oldest workspace is the existing production workspace.  It remains
    # unrestricted, so introducing subscriptions cannot interrupt its sync.
    op.execute(
        "UPDATE mobile_organizations SET is_legacy_workspace = true "
        "WHERE id = (SELECT MIN(id) FROM mobile_organizations)"
    )
    op.create_table(
        "cloud_subscriptions",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("organization_id", sa.BigInteger(), nullable=False),
        sa.Column("plan_code", sa.String(length=32), nullable=False, server_default="trial"),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="trial"),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("payment_provider", sa.String(length=32), nullable=True),
        sa.Column("payment_reference", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["organization_id"], ["mobile_organizations.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("organization_id"),
        sa.UniqueConstraint("payment_reference"),
    )
    op.create_index("ix_cloud_subscriptions_organization_id", "cloud_subscriptions", ["organization_id"])


def downgrade() -> None:
    op.drop_table("cloud_subscriptions")
    op.drop_column("mobile_organizations", "is_legacy_workspace")
    op.drop_column("mobile_organizations", "hosting_mode")
