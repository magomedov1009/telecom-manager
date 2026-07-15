"""warehouse inventory item classification

Revision ID: 202607060003a
Revises: 202607060003
Create Date: 2026-07-08
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "202607060003a"
down_revision = "202607060003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    item_type_enum = postgresql.ENUM("MATERIAL", "EQUIPMENT", name="inventory_item_type", create_type=False)
    item_type_enum.create(op.get_bind(), checkfirst=True)
    op.add_column("materials", sa.Column("item_type", item_type_enum, nullable=True))
    op.add_column("materials", sa.Column("category", sa.String(length=128), nullable=True))
    op.add_column("materials", sa.Column("unit_name", sa.String(length=64), nullable=True))
    op.execute("UPDATE materials SET item_type = 'MATERIAL', unit_name = CASE WHEN unit = 'PIECE' THEN 'шт.' ELSE 'м' END")
    op.execute("UPDATE materials SET item_type = 'EQUIPMENT', category = 'ONU', unit_name = 'шт.' WHERE upper(name) = 'ONU'")
    op.execute("UPDATE materials SET category = 'Кабель' WHERE category IS NULL AND upper(name) <> 'ONU'")
    op.alter_column("materials", "item_type", nullable=False)
    op.create_index("ix_materials_item_type", "materials", ["item_type"])
    op.create_index("ix_materials_category", "materials", ["category"])


def downgrade() -> None:
    op.drop_index("ix_materials_category", table_name="materials")
    op.drop_index("ix_materials_item_type", table_name="materials")
    op.drop_column("materials", "unit_name")
    op.drop_column("materials", "category")
    op.drop_column("materials", "item_type")
    item_type_enum = postgresql.ENUM("MATERIAL", "EQUIPMENT", name="inventory_item_type", create_type=False)
    item_type_enum.drop(op.get_bind(), checkfirst=True)
