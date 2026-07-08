"""multiprovider architecture

Revision ID: 202607060004
Revises: 202607060003
Create Date: 2026-07-08
"""

from alembic import op
import sqlalchemy as sa

revision = "202607060004"
down_revision = "202607060003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "providers",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_providers_id"), "providers", ["id"])
    op.create_index(op.f("ix_providers_name"), "providers", ["name"])
    op.create_index(op.f("ix_providers_is_active"), "providers", ["is_active"])

    op.execute("INSERT INTO providers (name, description, is_active) VALUES ('ELLKO', 'Migrated provider', true) ON CONFLICT (name) DO NOTHING")
    op.execute("INSERT INTO providers (name, description, is_active) VALUES ('OPTIMASET', 'Migrated provider', true) ON CONFLICT (name) DO NOTHING")

    op.add_column("clients", sa.Column("provider_id", sa.BigInteger(), nullable=True))
    op.create_index(op.f("ix_clients_provider_id"), "clients", ["provider_id"])
    op.create_foreign_key("fk_clients_provider_id_providers", "clients", "providers", ["provider_id"], ["id"], ondelete="RESTRICT")
    op.execute("UPDATE clients SET provider_id = providers.id FROM providers WHERE providers.name = clients.provider::text")
    op.execute("UPDATE clients SET provider_id = (SELECT id FROM providers ORDER BY id LIMIT 1) WHERE provider_id IS NULL")
    op.alter_column("clients", "provider_id", nullable=False)

    op.add_column("expenses", sa.Column("provider_id", sa.BigInteger(), nullable=True))
    op.create_index(op.f("ix_expenses_provider_id"), "expenses", ["provider_id"])
    op.create_foreign_key("fk_expenses_provider_id_providers", "expenses", "providers", ["provider_id"], ["id"], ondelete="RESTRICT")
    op.execute("UPDATE expenses SET provider_id = (SELECT id FROM providers ORDER BY id LIMIT 1) WHERE provider_id IS NULL")
    op.alter_column("expenses", "provider_id", nullable=False)

    op.add_column("finance_transactions", sa.Column("provider_id", sa.BigInteger(), nullable=True))
    op.create_index(op.f("ix_finance_transactions_provider_id"), "finance_transactions", ["provider_id"])
    op.create_foreign_key("fk_finance_transactions_provider_id_providers", "finance_transactions", "providers", ["provider_id"], ["id"], ondelete="SET NULL")
    op.execute("UPDATE finance_transactions ft SET provider_id = c.provider_id FROM connections cn JOIN clients c ON c.id = cn.client_id WHERE ft.connection_id = cn.id")
    op.execute("UPDATE finance_transactions ft SET provider_id = e.provider_id FROM expenses e WHERE ft.expense_id = e.id AND ft.provider_id IS NULL")
    op.execute("UPDATE finance_transactions SET provider_id = (SELECT id FROM providers ORDER BY id LIMIT 1) WHERE provider_id IS NULL")

    op.add_column("inventory_transactions", sa.Column("provider_id", sa.BigInteger(), nullable=True))
    op.create_index(op.f("ix_inventory_transactions_provider_id"), "inventory_transactions", ["provider_id"])
    op.create_foreign_key("fk_inventory_transactions_provider_id_providers", "inventory_transactions", "providers", ["provider_id"], ["id"], ondelete="SET NULL")
    op.execute("UPDATE inventory_transactions it SET provider_id = c.provider_id FROM connections cn JOIN clients c ON c.id = cn.client_id WHERE it.connection_id = cn.id")


def downgrade() -> None:
    op.drop_constraint("fk_inventory_transactions_provider_id_providers", "inventory_transactions", type_="foreignkey")
    op.drop_index(op.f("ix_inventory_transactions_provider_id"), table_name="inventory_transactions")
    op.drop_column("inventory_transactions", "provider_id")
    op.drop_constraint("fk_finance_transactions_provider_id_providers", "finance_transactions", type_="foreignkey")
    op.drop_index(op.f("ix_finance_transactions_provider_id"), table_name="finance_transactions")
    op.drop_column("finance_transactions", "provider_id")
    op.drop_constraint("fk_expenses_provider_id_providers", "expenses", type_="foreignkey")
    op.drop_index(op.f("ix_expenses_provider_id"), table_name="expenses")
    op.drop_column("expenses", "provider_id")
    op.drop_constraint("fk_clients_provider_id_providers", "clients", type_="foreignkey")
    op.drop_index(op.f("ix_clients_provider_id"), table_name="clients")
    op.drop_column("clients", "provider_id")
    op.drop_index(op.f("ix_providers_is_active"), table_name="providers")
    op.drop_index(op.f("ix_providers_name"), table_name="providers")
    op.drop_index(op.f("ix_providers_id"), table_name="providers")
    op.drop_table("providers")
