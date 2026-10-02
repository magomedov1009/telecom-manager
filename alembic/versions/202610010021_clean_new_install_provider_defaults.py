"""Remove historical demo providers from genuinely empty installations.

Revision ID: 202610010021
Revises: 202610010020
Create Date: 2026-10-01
"""

from alembic import op
import sqlalchemy as sa

from app.core.config import settings


revision = "202610010021"
down_revision = "202610010020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if not settings.bootstrap_clean_demo_provider_catalog:
        return

    connection = op.get_bind()

    # Never change a workspace that has been initialized for mobile sync or
    # contains operational data. Historical installs keep their existing
    # providers, warehouses, and all related records.
    if connection.scalar(sa.text("SELECT COUNT(*) FROM mobile_organizations")):
        return
    for table in (
        "clients",
        "connections",
        "connection_materials",
        "extra_works",
        "extra_work_materials",
        "expenses",
        "finance_transactions",
        "inventory_transactions",
        "material_debt_settlements",
    ):
        if connection.scalar(sa.text(f"SELECT EXISTS (SELECT 1 FROM {table})")):
            return

    # Also preserve installations where an administrator already changed the
    # seeded catalog, even if they have not entered operational records yet.
    if connection.scalar(sa.text("SELECT COUNT(*) FROM providers")) != 2:
        return
    if connection.scalar(
        sa.text(
            """
            SELECT COUNT(*) FROM providers
            WHERE (name, description) IN (
                ('ELLKO', 'Migrated provider'),
                ('OPTIMASET', 'Migrated provider')
            )
            AND is_active IS TRUE
            """
        )
    ) != 2:
        return
    if connection.scalar(sa.text("SELECT COUNT(*) FROM warehouses")) != 2:
        return
    if connection.scalar(
        sa.text(
            "SELECT COUNT(*) FROM warehouses "
            "WHERE name IN ('Эллко', 'Оптимасеть') AND active IS TRUE"
        )
    ) != 2:
        return

    connection.execute(
        sa.text(
            "DELETE FROM warehouses WHERE name IN ('Эллко', 'Оптимасеть')"
        )
    )
    connection.execute(
        sa.text(
            "DELETE FROM providers WHERE description = 'Migrated provider' "
            "AND name IN ('ELLKO', 'OPTIMASET')"
        )
    )


def downgrade() -> None:
    # Removed rows were demo defaults. Restoring them would risk reintroducing
    # provider-specific assumptions, so downgrade intentionally leaves data as-is.
    pass
