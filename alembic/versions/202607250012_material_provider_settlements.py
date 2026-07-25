"""material provider settlements

Revision ID: 202607250012
Revises: 202607060011
Create Date: 2026-07-25
"""

import sqlalchemy as sa
from alembic import op


revision = "202607250012"
down_revision = "202607060011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("warehouses", sa.Column("provider_id", sa.BigInteger(), nullable=True))
    op.create_index(op.f("ix_warehouses_provider_id"), "warehouses", ["provider_id"])
    op.create_foreign_key(
        "fk_warehouses_provider_id_providers",
        "warehouses",
        "providers",
        ["provider_id"],
        ["id"],
        ondelete="SET NULL",
    )

    op.add_column(
        "inventory_transactions",
        sa.Column("counterpart_warehouse_id", sa.BigInteger(), nullable=True),
    )
    op.create_index(
        op.f("ix_inventory_transactions_counterpart_warehouse_id"),
        "inventory_transactions",
        ["counterpart_warehouse_id"],
    )
    op.create_foreign_key(
        "fk_inventory_transactions_counterpart_warehouse_id_warehouses",
        "inventory_transactions",
        "warehouses",
        ["counterpart_warehouse_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # Existing installations use these two warehouse/provider pairs. Matching is
    # deliberately tolerant of case, spaces and Cyrillic/Latin spelling.
    op.execute(
        """
        UPDATE warehouses w
        SET provider_id = p.id
        FROM providers p
        WHERE
            (lower(replace(w.name, ' ', '')) IN ('эллко', 'ellko')
             AND lower(replace(p.name, ' ', '')) IN ('эллко', 'ellko'))
            OR
            (lower(replace(w.name, ' ', '')) IN ('оптимасеть', 'оптимасет', 'optimaset')
             AND lower(replace(p.name, ' ', '')) IN ('оптимасеть', 'оптимасет', 'optimaset'));
        """
    )

    # Both rows of an old transfer are inserted in one PostgreSQL transaction,
    # so created_at, user, material and absolute quantity identify the pair.
    op.execute(
        """
        WITH outgoing AS (
            SELECT
                id,
                warehouse_id,
                user_id,
                material_id,
                abs(quantity) AS quantity,
                created_at,
                row_number() OVER (
                    PARTITION BY user_id, material_id, abs(quantity), created_at
                    ORDER BY id
                ) AS pair_number
            FROM inventory_transactions
            WHERE operation_type = 'TRANSFER_OUT'
              AND counterpart_warehouse_id IS NULL
        ),
        incoming AS (
            SELECT
                id,
                warehouse_id,
                user_id,
                material_id,
                quantity,
                created_at,
                row_number() OVER (
                    PARTITION BY user_id, material_id, quantity, created_at
                    ORDER BY id
                ) AS pair_number
            FROM inventory_transactions
            WHERE operation_type = 'TRANSFER_IN'
              AND counterpart_warehouse_id IS NULL
        ),
        transfer_pairs AS (
            SELECT
                outgoing.id AS out_id,
                incoming.id AS in_id,
                outgoing.warehouse_id AS source_id,
                incoming.warehouse_id AS destination_id
            FROM outgoing
            JOIN incoming
              ON incoming.user_id = outgoing.user_id
             AND incoming.material_id = outgoing.material_id
             AND incoming.quantity = outgoing.quantity
             AND incoming.created_at = outgoing.created_at
             AND incoming.pair_number = outgoing.pair_number
             AND incoming.warehouse_id <> outgoing.warehouse_id
        )
        UPDATE inventory_transactions target_transaction
        SET counterpart_warehouse_id = CASE
            WHEN target_transaction.id = pair.out_id THEN pair.destination_id
            ELSE pair.source_id
        END
        FROM transfer_pairs pair
        WHERE target_transaction.id IN (pair.out_id, pair.in_id);
        """
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_inventory_transactions_counterpart_warehouse_id_warehouses",
        "inventory_transactions",
        type_="foreignkey",
    )
    op.drop_index(
        op.f("ix_inventory_transactions_counterpart_warehouse_id"),
        table_name="inventory_transactions",
    )
    op.drop_column("inventory_transactions", "counterpart_warehouse_id")
    op.drop_constraint(
        "fk_warehouses_provider_id_providers",
        "warehouses",
        type_="foreignkey",
    )
    op.drop_index(op.f("ix_warehouses_provider_id"), table_name="warehouses")
    op.drop_column("warehouses", "provider_id")
