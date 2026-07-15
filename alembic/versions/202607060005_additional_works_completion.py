"""additional works completion

Revision ID: 202607060005
Revises: 202607060004
Create Date: 2026-07-08
"""

from alembic import op
import sqlalchemy as sa

revision = "202607060005"
down_revision = "202607060004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "extra_work_types",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("default_price", sa.Numeric(14, 2), nullable=True),
        sa.Column("default_office_amount", sa.Numeric(14, 2), nullable=True),
        sa.Column("requires_materials", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("requires_equipment", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_extra_work_types_id"), "extra_work_types", ["id"])
    op.create_index(op.f("ix_extra_work_types_name"), "extra_work_types", ["name"])
    op.create_index(op.f("ix_extra_work_types_is_active"), "extra_work_types", ["is_active"])

    for name in ["Настройка роутера", "Замена ONU", "Перенос точки", "Протяжка кабеля", "Настройка IPTV", "Диагностика", "Другое"]:
        op.execute(sa.text("INSERT INTO extra_work_types (name, is_active) VALUES (:name, true) ON CONFLICT (name) DO NOTHING").bindparams(name=name))

    op.add_column("extra_works", sa.Column("provider_id", sa.BigInteger(), nullable=True))
    op.add_column("extra_works", sa.Column("work_type_id", sa.BigInteger(), nullable=True))
    op.add_column("extra_works", sa.Column("work_date", sa.Date(), nullable=True))
    op.add_column("extra_works", sa.Column("office_amount", sa.Numeric(14, 2), nullable=False, server_default="0"))
    op.add_column("extra_works", sa.Column("installer_amount", sa.Numeric(14, 2), nullable=False, server_default="0"))
    op.add_column("extra_works", sa.Column("extra_expenses", sa.Numeric(14, 2), nullable=False, server_default="0"))
    op.add_column("extra_works", sa.Column("status", sa.String(length=32), nullable=False, server_default="completed"))
    op.create_index(op.f("ix_extra_works_provider_id"), "extra_works", ["provider_id"])
    op.create_index(op.f("ix_extra_works_work_type_id"), "extra_works", ["work_type_id"])
    op.create_index(op.f("ix_extra_works_work_date"), "extra_works", ["work_date"])
    op.create_index(op.f("ix_extra_works_status"), "extra_works", ["status"])
    op.create_foreign_key("fk_extra_works_provider_id_providers", "extra_works", "providers", ["provider_id"], ["id"], ondelete="RESTRICT")
    op.create_foreign_key("fk_extra_works_work_type_id_extra_work_types", "extra_works", "extra_work_types", ["work_type_id"], ["id"], ondelete="SET NULL")
    op.execute("UPDATE extra_works ew SET provider_id = c.provider_id FROM clients c WHERE ew.client_id = c.id")
    op.execute("UPDATE extra_works SET provider_id = (SELECT id FROM providers ORDER BY id LIMIT 1) WHERE provider_id IS NULL")
    op.execute("UPDATE extra_works SET work_date = created_at::date WHERE work_date IS NULL")
    op.execute("UPDATE extra_works SET installer_amount = amount WHERE installer_amount = 0 AND office_amount = 0")
    op.alter_column("extra_works", "provider_id", nullable=False)
    op.alter_column("extra_works", "work_date", nullable=False)

    op.create_table(
        "extra_work_materials",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("extra_work_id", sa.BigInteger(), nullable=False),
        sa.Column("material_id", sa.BigInteger(), nullable=False),
        sa.Column("quantity", sa.Numeric(14, 3), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_extra_work_materials_quantity_positive"),
        sa.ForeignKeyConstraint(["extra_work_id"], ["extra_works.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["material_id"], ["materials.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_extra_work_materials_id"), "extra_work_materials", ["id"])
    op.create_index(op.f("ix_extra_work_materials_extra_work_id"), "extra_work_materials", ["extra_work_id"])
    op.create_index(op.f("ix_extra_work_materials_material_id"), "extra_work_materials", ["material_id"])

    op.execute("UPDATE finance_transactions ft SET provider_id = ew.provider_id FROM extra_works ew WHERE ft.extra_work_id = ew.id AND ft.provider_id IS NULL")


def downgrade() -> None:
    op.drop_index(op.f("ix_extra_work_materials_material_id"), table_name="extra_work_materials")
    op.drop_index(op.f("ix_extra_work_materials_extra_work_id"), table_name="extra_work_materials")
    op.drop_index(op.f("ix_extra_work_materials_id"), table_name="extra_work_materials")
    op.drop_table("extra_work_materials")
    op.drop_constraint("fk_extra_works_work_type_id_extra_work_types", "extra_works", type_="foreignkey")
    op.drop_constraint("fk_extra_works_provider_id_providers", "extra_works", type_="foreignkey")
    op.drop_index(op.f("ix_extra_works_status"), table_name="extra_works")
    op.drop_index(op.f("ix_extra_works_work_date"), table_name="extra_works")
    op.drop_index(op.f("ix_extra_works_work_type_id"), table_name="extra_works")
    op.drop_index(op.f("ix_extra_works_provider_id"), table_name="extra_works")
    op.drop_column("extra_works", "status")
    op.drop_column("extra_works", "extra_expenses")
    op.drop_column("extra_works", "installer_amount")
    op.drop_column("extra_works", "office_amount")
    op.drop_column("extra_works", "work_date")
    op.drop_column("extra_works", "work_type_id")
    op.drop_column("extra_works", "provider_id")
    op.drop_index(op.f("ix_extra_work_types_is_active"), table_name="extra_work_types")
    op.drop_index(op.f("ix_extra_work_types_name"), table_name="extra_work_types")
    op.drop_index(op.f("ix_extra_work_types_id"), table_name="extra_work_types")
    op.drop_table("extra_work_types")
