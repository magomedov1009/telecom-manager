from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "202610010021_clean_new_install_provider_defaults.py"
)
SPEC = importlib.util.spec_from_file_location(
    "clean_new_install_provider_defaults",
    MIGRATION_PATH,
)
assert SPEC is not None and SPEC.loader is not None
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class MigrationConnection:
    def __init__(self, *, mobile_organizations: int = 0, populated_table: str | None = None,
                 providers: int = 2, seeded_providers: int = 2,
                 warehouses: int = 2, seeded_warehouses: int = 2) -> None:
        self.mobile_organizations = mobile_organizations
        self.populated_table = populated_table
        self.providers = providers
        self.seeded_providers = seeded_providers
        self.warehouses = warehouses
        self.seeded_warehouses = seeded_warehouses
        self.executed: list[str] = []

    def scalar(self, statement):
        sql = " ".join(str(statement).split())
        if sql == "SELECT COUNT(*) FROM mobile_organizations":
            return self.mobile_organizations
        if sql.startswith("SELECT EXISTS (SELECT 1 FROM "):
            table = sql.removeprefix("SELECT EXISTS (SELECT 1 FROM ").split(")", 1)[0]
            return int(table == self.populated_table)
        if sql == "SELECT COUNT(*) FROM providers":
            return self.providers
        if "FROM providers WHERE (name, description) IN" in sql:
            return self.seeded_providers
        if sql == "SELECT COUNT(*) FROM warehouses":
            return self.warehouses
        if "FROM warehouses WHERE name IN" in sql:
            return self.seeded_warehouses
        raise AssertionError(f"Unexpected migration query: {sql}")

    def execute(self, statement):
        self.executed.append(" ".join(str(statement).split()))


class CleanDemoProviderMigrationTests(unittest.TestCase):
    def run_migration(self, connection: MigrationConnection, enabled: bool = True) -> None:
        with (
            patch.object(
                MIGRATION.settings,
                "bootstrap_clean_demo_provider_catalog",
                enabled,
            ),
            patch.object(MIGRATION.op, "get_bind", return_value=connection),
        ):
            MIGRATION.upgrade()

    def test_deletes_only_exact_demo_catalog_from_an_empty_database(self) -> None:
        connection = MigrationConnection()

        self.run_migration(connection)

        self.assertEqual(len(connection.executed), 2)
        self.assertIn("DELETE FROM warehouses", connection.executed[0])
        self.assertIn("DELETE FROM providers", connection.executed[1])

    def test_keeps_catalog_when_organization_or_operational_data_exists(self) -> None:
        for connection in (
            MigrationConnection(mobile_organizations=1),
            MigrationConnection(populated_table="connections"),
            MigrationConnection(populated_table="material_debt_settlements"),
        ):
            with self.subTest(connection=connection.populated_table or "organization"):
                self.run_migration(connection)
                self.assertEqual(connection.executed, [])

    def test_keeps_catalog_when_it_was_customized(self) -> None:
        for connection in (
            MigrationConnection(providers=3),
            MigrationConnection(seeded_providers=1),
            MigrationConnection(warehouses=3),
            MigrationConnection(seeded_warehouses=1),
        ):
            with self.subTest(connection=connection.__dict__):
                self.run_migration(connection)
                self.assertEqual(connection.executed, [])

    def test_does_nothing_unless_new_install_bootstrap_is_explicitly_enabled(self) -> None:
        connection = MigrationConnection()
        with (
            patch.object(
                MIGRATION.settings,
                "bootstrap_clean_demo_provider_catalog",
                False,
            ),
            patch.object(MIGRATION.op, "get_bind") as get_bind,
        ):
            MIGRATION.upgrade()

        get_bind.assert_not_called()
        self.assertEqual(connection.executed, [])


if __name__ == "__main__":
    unittest.main()
