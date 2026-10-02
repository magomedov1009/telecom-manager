from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

from sqlalchemy import create_engine, text


MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "202610010018_cloud_subscriptions.py"
)
SPEC = importlib.util.spec_from_file_location(
    "cloud_subscriptions_migration",
    MIGRATION_PATH,
)
assert SPEC is not None and SPEC.loader is not None
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class CloudSubscriptionMigrationTests(unittest.TestCase):
    def test_grandfathers_every_workspace_that_existed_before_billing(self) -> None:
        engine = create_engine("sqlite:///:memory:")
        with engine.begin() as connection:
            connection.execute(text(
                "CREATE TABLE mobile_organizations "
                "(id INTEGER PRIMARY KEY, is_legacy_workspace BOOLEAN NOT NULL)"
            ))
            connection.execute(text(
                "INSERT INTO mobile_organizations (id, is_legacy_workspace) "
                "VALUES (1, false), (2, false), (3, false)"
            ))

            def execute(statement) -> None:
                sql = str(statement)
                if sql.startswith("UPDATE mobile_organizations"):
                    connection.exec_driver_sql(sql)

            with (
                patch.object(MIGRATION.op, "add_column"),
                patch.object(MIGRATION.op, "execute", side_effect=execute),
                patch.object(MIGRATION.op, "create_table"),
                patch.object(MIGRATION.op, "create_index"),
            ):
                MIGRATION.upgrade()

            legacy_ids = connection.execute(text(
                "SELECT id FROM mobile_organizations "
                "WHERE is_legacy_workspace = true ORDER BY id"
            )).scalars().all()

        engine.dispose()
        self.assertEqual(legacy_ids, [1, 2, 3])


if __name__ == "__main__":
    unittest.main()
