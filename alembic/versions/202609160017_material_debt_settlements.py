"""manual material debt settlements

Revision ID: 202609160017
Revises: 202608010016
Create Date: 2026-09-16
"""

import sqlalchemy as sa
from alembic import op


revision = "202609160017"
down_revision = "202608010016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "material_debt_settlements",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("debtor_provider_id", sa.BigInteger(), nullable=False),
        sa.Column("creditor_provider_id", sa.BigInteger(), nullable=False),
        sa.Column("material_id", sa.BigInteger(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("quantity", sa.Numeric(14, 3), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("quantity > 0", name="ck_material_debt_settlements_quantity_positive"),
        sa.CheckConstraint("debtor_provider_id <> creditor_provider_id", name="ck_material_debt_settlements_different_providers"),
        sa.ForeignKeyConstraint(["debtor_provider_id"], ["providers.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["creditor_provider_id"], ["providers.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["material_id"], ["materials.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_material_debt_settlements_debtor_provider_id", "material_debt_settlements", ["debtor_provider_id"])
    op.create_index("ix_material_debt_settlements_creditor_provider_id", "material_debt_settlements", ["creditor_provider_id"])
    op.create_index("ix_material_debt_settlements_material_id", "material_debt_settlements", ["material_id"])


def downgrade() -> None:
    op.drop_table("material_debt_settlements")
