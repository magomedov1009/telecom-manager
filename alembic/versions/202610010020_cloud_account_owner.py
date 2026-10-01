"""add cloud organization owner

Revision ID: 202610010020
Revises: 202610010019
Create Date: 2026-10-01
"""

import sqlalchemy as sa
from alembic import op


revision = "202610010020"
down_revision = "202610010019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("mobile_organizations", sa.Column("owner_user_id", sa.BigInteger(), nullable=True))
    op.create_foreign_key("fk_mobile_organizations_owner_user_id", "mobile_organizations", "users", ["owner_user_id"], ["id"], ondelete="SET NULL")
    op.create_index("ix_mobile_organizations_owner_user_id", "mobile_organizations", ["owner_user_id"])


def downgrade() -> None:
    op.drop_index("ix_mobile_organizations_owner_user_id", table_name="mobile_organizations")
    op.drop_constraint("fk_mobile_organizations_owner_user_id", "mobile_organizations", type_="foreignkey")
    op.drop_column("mobile_organizations", "owner_user_id")
