"""initial schema

Revision ID: 202607060001
Revises:
Create Date: 2026-07-06 00:01:00
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "202607060001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


user_role = postgresql.ENUM("ADMIN", "OFFICE", "INSTALLER", name="user_role")
material_unit = postgresql.ENUM("PIECE", "METER", name="material_unit")
provider = postgresql.ENUM("ELLKO", "OPTIMASET", name="provider")
inventory_transaction_type = postgresql.ENUM(
    "RECEIPT",
    "CONNECTION",
    "TRANSFER_IN",
    "TRANSFER_OUT",
    "RETURN",
    "ISSUE_TO_THIRD_PARTY",
    "WRITE_OFF",
    "ADJUSTMENT",
    name="inventory_transaction_type",
)
connection_type = postgresql.ENUM(
    "NEW",
    "RECONNECT",
    "WITHOUT_MATERIALS",
    "ONU_REPLACE",
    "CABLE_REPLACE",
    "CUSTOM",
    name="connection_type",
)
finance_transaction_type = postgresql.ENUM(
    "CONNECTION",
    "EXTRA_WORK",
    "EXPENSE",
    "PAYMENT_TO_OFFICE",
    "PAYMENT_FROM_OFFICE",
    "ADJUSTMENT",
    name="finance_transaction_type",
)
expense_category = postgresql.ENUM(
    "FUEL",
    "TOOLS",
    "TRANSPORT",
    "COMMUNICATION",
    "OTHER",
    name="expense_category",
)
event_action = postgresql.ENUM(
    "CREATE",
    "UPDATE",
    "DELETE",
    "LOGIN",
    "LOGOUT",
    "INVENTORY_TRANSACTION",
    "FINANCE_OPERATION",
    name="event_action",
)


def upgrade() -> None:
    bind = op.get_bind()
    for enum_type in (
        user_role,
        material_unit,
        provider,
        inventory_transaction_type,
        connection_type,
        finance_transaction_type,
        expense_category,
        event_action,
    ):
        enum_type.create(bind, checkfirst=True)

    op.create_table(
        "users",
        sa.Column("username", sa.String(length=64), nullable=False),
        sa.Column("full_name", sa.String(length=255), nullable=False),
        sa.Column("hashed_password", sa.String(length=255), nullable=False),
        sa.Column("role", user_role, nullable=False),
        sa.Column("phone", sa.String(length=32), nullable=True),
        sa.Column("email", sa.String(length=255), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email"),
        sa.UniqueConstraint("phone"),
        sa.UniqueConstraint("username"),
    )
    op.create_index(op.f("ix_users_id"), "users", ["id"])
    op.create_index(op.f("ix_users_username"), "users", ["username"])

    op.create_table(
        "warehouses",
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_warehouses_id"), "warehouses", ["id"])
    op.create_index(op.f("ix_warehouses_name"), "warehouses", ["name"])

    op.create_table(
        "materials",
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column("unit", material_unit, nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_materials_id"), "materials", ["id"])
    op.create_index(op.f("ix_materials_name"), "materials", ["name"])

    op.create_table(
        "clients",
        sa.Column("provider", provider, nullable=False),
        sa.Column("contract_number", sa.String(length=64), nullable=False),
        sa.Column("login", sa.String(length=128), nullable=False),
        sa.Column("address", sa.String(length=500), nullable=False),
        sa.Column("phone", sa.String(length=32), nullable=True),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("contract_number"),
        sa.UniqueConstraint("login"),
    )
    op.create_index(op.f("ix_clients_contract_number"), "clients", ["contract_number"])
    op.create_index(op.f("ix_clients_id"), "clients", ["id"])
    op.create_index(op.f("ix_clients_login"), "clients", ["login"])
    op.create_index(op.f("ix_clients_phone"), "clients", ["phone"])
    op.create_index(op.f("ix_clients_provider"), "clients", ["provider"])

    op.create_table(
        "connections",
        sa.Column("client_id", sa.BigInteger(), nullable=False),
        sa.Column("warehouse_id", sa.BigInteger(), nullable=False),
        sa.Column("connection_type", connection_type, nullable=False),
        sa.Column("connection_date", sa.Date(), nullable=False),
        sa.Column("installer_id", sa.BigInteger(), nullable=False),
        sa.Column("price", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("office_amount", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("installer_amount", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("price >= 0", name="ck_connections_price_non_negative"),
        sa.CheckConstraint("office_amount >= 0", name="ck_connections_office_amount_non_negative"),
        sa.CheckConstraint("installer_amount >= 0", name="ck_connections_installer_amount_non_negative"),
        sa.ForeignKeyConstraint(["client_id"], ["clients.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["installer_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_connections_client_id"), "connections", ["client_id"])
    op.create_index(op.f("ix_connections_connection_date"), "connections", ["connection_date"])
    op.create_index(op.f("ix_connections_connection_type"), "connections", ["connection_type"])
    op.create_index(op.f("ix_connections_id"), "connections", ["id"])
    op.create_index(op.f("ix_connections_installer_id"), "connections", ["installer_id"])
    op.create_index(op.f("ix_connections_warehouse_id"), "connections", ["warehouse_id"])

    op.create_table(
        "expenses",
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("category", expense_category, nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("amount > 0", name="ck_expenses_amount_positive"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_expenses_category"), "expenses", ["category"])
    op.create_index(op.f("ix_expenses_id"), "expenses", ["id"])
    op.create_index(op.f("ix_expenses_user_id"), "expenses", ["user_id"])

    op.create_table(
        "event_logs",
        sa.Column("actor_id", sa.BigInteger(), nullable=True),
        sa.Column("action", event_action, nullable=False),
        sa.Column("entity_type", sa.String(length=128), nullable=False),
        sa.Column("entity_id", sa.BigInteger(), nullable=True),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("ip_address", sa.String(length=45), nullable=True),
        sa.Column("user_agent", sa.String(length=512), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["actor_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_event_logs_action"), "event_logs", ["action"])
    op.create_index(op.f("ix_event_logs_actor_id"), "event_logs", ["actor_id"])
    op.create_index(op.f("ix_event_logs_entity_id"), "event_logs", ["entity_id"])
    op.create_index(op.f("ix_event_logs_entity_type"), "event_logs", ["entity_type"])
    op.create_index(op.f("ix_event_logs_id"), "event_logs", ["id"])

    op.create_table(
        "connection_materials",
        sa.Column("connection_id", sa.BigInteger(), nullable=False),
        sa.Column("material_id", sa.BigInteger(), nullable=False),
        sa.Column("quantity", sa.Numeric(14, 3), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_connection_materials_quantity_positive"),
        sa.ForeignKeyConstraint(["connection_id"], ["connections.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["material_id"], ["materials.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_connection_materials_connection_id"), "connection_materials", ["connection_id"])
    op.create_index(op.f("ix_connection_materials_id"), "connection_materials", ["id"])
    op.create_index(op.f("ix_connection_materials_material_id"), "connection_materials", ["material_id"])

    op.create_table(
        "extra_works",
        sa.Column("client_id", sa.BigInteger(), nullable=False),
        sa.Column("connection_id", sa.BigInteger(), nullable=True),
        sa.Column("installer_id", sa.BigInteger(), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["client_id"], ["clients.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["connection_id"], ["connections.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["installer_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_extra_works_client_id"), "extra_works", ["client_id"])
    op.create_index(op.f("ix_extra_works_connection_id"), "extra_works", ["connection_id"])
    op.create_index(op.f("ix_extra_works_id"), "extra_works", ["id"])
    op.create_index(op.f("ix_extra_works_installer_id"), "extra_works", ["installer_id"])

    op.create_table(
        "inventory_transactions",
        sa.Column("warehouse_id", sa.BigInteger(), nullable=False),
        sa.Column("material_id", sa.BigInteger(), nullable=False),
        sa.Column("connection_id", sa.BigInteger(), nullable=True),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("operation_type", inventory_transaction_type, nullable=False),
        sa.Column("quantity", sa.Numeric(14, 3), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("quantity <> 0", name="ck_inventory_transactions_quantity_non_zero"),
        sa.ForeignKeyConstraint(["connection_id"], ["connections.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["material_id"], ["materials.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inventory_transactions_connection_id"), "inventory_transactions", ["connection_id"])
    op.create_index(op.f("ix_inventory_transactions_id"), "inventory_transactions", ["id"])
    op.create_index(op.f("ix_inventory_transactions_material_id"), "inventory_transactions", ["material_id"])
    op.create_index(op.f("ix_inventory_transactions_operation_type"), "inventory_transactions", ["operation_type"])
    op.create_index(op.f("ix_inventory_transactions_user_id"), "inventory_transactions", ["user_id"])
    op.create_index(op.f("ix_inventory_transactions_warehouse_id"), "inventory_transactions", ["warehouse_id"])
    op.create_index("ix_inventory_transactions_stock_lookup", "inventory_transactions", ["warehouse_id", "material_id"])

    op.create_table(
        "finance_transactions",
        sa.Column("connection_id", sa.BigInteger(), nullable=True),
        sa.Column("expense_id", sa.BigInteger(), nullable=True),
        sa.Column("extra_work_id", sa.BigInteger(), nullable=True),
        sa.Column("user_id", sa.BigInteger(), nullable=True),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("transaction_type", finance_transaction_type, nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("amount <> 0", name="ck_finance_transactions_amount_non_zero"),
        sa.CheckConstraint("num_nonnulls(connection_id, expense_id, extra_work_id) <= 1", name="ck_finance_transactions_single_source"),
        sa.ForeignKeyConstraint(["connection_id"], ["connections.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["expense_id"], ["expenses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["extra_work_id"], ["extra_works.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_finance_transactions_connection_id"), "finance_transactions", ["connection_id"])
    op.create_index(op.f("ix_finance_transactions_expense_id"), "finance_transactions", ["expense_id"])
    op.create_index(op.f("ix_finance_transactions_extra_work_id"), "finance_transactions", ["extra_work_id"])
    op.create_index(op.f("ix_finance_transactions_id"), "finance_transactions", ["id"])
    op.create_index(op.f("ix_finance_transactions_user_id"), "finance_transactions", ["user_id"])
    op.create_index(op.f("ix_finance_transactions_transaction_type"), "finance_transactions", ["transaction_type"])

    seed_initial_data()


def downgrade() -> None:
    for index_name, table_name in (
        (op.f("ix_finance_transactions_transaction_type"), "finance_transactions"),
        (op.f("ix_finance_transactions_id"), "finance_transactions"),
        (op.f("ix_finance_transactions_user_id"), "finance_transactions"),
        (op.f("ix_finance_transactions_extra_work_id"), "finance_transactions"),
        (op.f("ix_finance_transactions_expense_id"), "finance_transactions"),
        (op.f("ix_finance_transactions_connection_id"), "finance_transactions"),
    ):
        op.drop_index(index_name, table_name=table_name)
    op.drop_table("finance_transactions")

    op.drop_index("ix_inventory_transactions_stock_lookup", table_name="inventory_transactions")
    for index_name in (
        op.f("ix_inventory_transactions_warehouse_id"),
        op.f("ix_inventory_transactions_user_id"),
        op.f("ix_inventory_transactions_operation_type"),
        op.f("ix_inventory_transactions_material_id"),
        op.f("ix_inventory_transactions_id"),
        op.f("ix_inventory_transactions_connection_id"),
    ):
        op.drop_index(index_name, table_name="inventory_transactions")
    op.drop_table("inventory_transactions")

    for table_name, index_names in (
        ("extra_works", (op.f("ix_extra_works_installer_id"), op.f("ix_extra_works_id"), op.f("ix_extra_works_connection_id"), op.f("ix_extra_works_client_id"))),
        ("connection_materials", (op.f("ix_connection_materials_material_id"), op.f("ix_connection_materials_id"), op.f("ix_connection_materials_connection_id"))),
        ("event_logs", (op.f("ix_event_logs_id"), op.f("ix_event_logs_entity_type"), op.f("ix_event_logs_entity_id"), op.f("ix_event_logs_actor_id"), op.f("ix_event_logs_action"))),
        ("expenses", (op.f("ix_expenses_user_id"), op.f("ix_expenses_id"), op.f("ix_expenses_category"))),
        ("connections", (op.f("ix_connections_warehouse_id"), op.f("ix_connections_installer_id"), op.f("ix_connections_id"), op.f("ix_connections_connection_type"), op.f("ix_connections_connection_date"), op.f("ix_connections_client_id"))),
        ("clients", (op.f("ix_clients_provider"), op.f("ix_clients_phone"), op.f("ix_clients_login"), op.f("ix_clients_id"), op.f("ix_clients_contract_number"))),
        ("materials", (op.f("ix_materials_name"), op.f("ix_materials_id"))),
        ("warehouses", (op.f("ix_warehouses_name"), op.f("ix_warehouses_id"))),
        ("users", (op.f("ix_users_username"), op.f("ix_users_id"))),
    ):
        for index_name in index_names:
            op.drop_index(index_name, table_name=table_name)
        op.drop_table(table_name)

    for enum_type in (
        event_action,
        expense_category,
        finance_transaction_type,
        connection_type,
        inventory_transaction_type,
        provider,
        material_unit,
        user_role,
    ):
        enum_type.drop(op.get_bind(), checkfirst=True)


def seed_initial_data() -> None:
    warehouses_table = sa.table(
        "warehouses",
        sa.column("name", sa.String),
        sa.column("active", sa.Boolean),
    )
    materials_table = sa.table(
        "materials",
        sa.column("name", sa.String),
        sa.column("unit", material_unit),
        sa.column("active", sa.Boolean),
    )
    users_table = sa.table(
        "users",
        sa.column("username", sa.String),
        sa.column("full_name", sa.String),
        sa.column("hashed_password", sa.String),
        sa.column("role", user_role),
        sa.column("is_active", sa.Boolean),
    )

    op.bulk_insert(
        warehouses_table,
        [
            {"name": "Эллко", "active": True},
            {"name": "Оптимасеть", "active": True},
        ],
    )
    op.bulk_insert(
        materials_table,
        [
            {"name": "ONU", "unit": "PIECE", "active": True},
            {"name": "Кабель витая пара", "unit": "METER", "active": True},
            {"name": "Кабель оптика круглая", "unit": "METER", "active": True},
            {"name": "Кабель оптика лапша", "unit": "METER", "active": True},
        ],
    )
    op.bulk_insert(
        users_table,
        [
            {
                "username": "admin",
                "full_name": "Administrator",
                "hashed_password": "pbkdf2_sha256$260000$telecom-manager-admin$ef202caeadca3d4d6d0224f5b28877578636576ce1647176065a45416c264a80",
                "role": "ADMIN",
                "is_active": True,
            },
        ],
    )










