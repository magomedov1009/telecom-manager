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
    / "202610040025_clean_cloud_bootstrap_admin.py"
)
SPEC = importlib.util.spec_from_file_location(
    "clean_cloud_bootstrap_admin_migration",
    MIGRATION_PATH,
)
assert SPEC is not None and SPEC.loader is not None
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class CleanCloudBootstrapAdminMigrationTests(unittest.TestCase):
    def run_migration(
        self,
        *,
        hosting_mode: str = "cloud",
        enabled: bool = True,
        admin_hash: str | None = None,
        user_count: int = 1,
        organization_count: int = 0,
        event_count: int = 0,
        full_name: str = "Administrator",
    ) -> list[str]:
        engine = create_engine("sqlite:///:memory:")
        executed: list[str] = []
        with engine.begin() as connection:
            connection.execute(text("CREATE TABLE mobile_organizations (id INTEGER PRIMARY KEY)"))
            connection.execute(
                text(
                    """CREATE TABLE users (
                        id INTEGER PRIMARY KEY,
                        username TEXT NOT NULL,
                        full_name TEXT NOT NULL,
                        hashed_password TEXT NOT NULL,
                        role TEXT NOT NULL,
                        is_active BOOLEAN NOT NULL,
                        last_login_at TEXT NULL,
                        phone TEXT NULL,
                        email TEXT NULL,
                        cloud_trial_used BOOLEAN NOT NULL,
                        comment TEXT NULL,
                        manager_id INTEGER NULL
                    )"""
                )
            )
            for table, column in MIGRATION._USER_ACTIVITY_TABLES.items():
                connection.execute(
                    text(f"CREATE TABLE {table} ({column} INTEGER NULL)")
                )
            for index in range(organization_count):
                connection.execute(
                    text("INSERT INTO mobile_organizations (id) VALUES (:id)"),
                    {"id": index + 1},
                )
            connection.execute(
                text(
                    """INSERT INTO users (
                        id, username, full_name, hashed_password, role, is_active,
                        last_login_at, phone, email, cloud_trial_used, comment,
                        manager_id
                    ) VALUES (1, 'admin', :full_name, :password_hash, 'ADMIN',
                              1, NULL, NULL, NULL, 0, NULL, NULL)"""
                ),
                {
                    "full_name": full_name,
                    "password_hash": admin_hash or MIGRATION._SEEDED_ADMIN_HASH,
                },
            )
            for index in range(1, user_count):
                connection.execute(
                    text(
                        """INSERT INTO users (
                            id, username, full_name, hashed_password, role,
                            is_active, cloud_trial_used
                        ) VALUES (:id, 'worker', 'Worker', 'other-hash',
                                  'INSTALLER', 1, 0)"""
                    ),
                    {"id": index + 1},
                )
            if event_count:
                connection.execute(
                    text("INSERT INTO event_logs (actor_id) VALUES (1)")
                )
            with (
                patch.object(MIGRATION.settings, "hosting_mode", hosting_mode),
                patch.object(
                    MIGRATION.settings,
                    "bootstrap_clean_cloud_defaults",
                    enabled,
                ),
                patch.object(MIGRATION.op, "get_bind", return_value=connection),
            ):
                MIGRATION.upgrade()
            usernames = connection.execute(
                text("SELECT username FROM users ORDER BY id")
            ).scalars().all()
            executed = list(usernames)
        engine.dispose()
        return executed

    def test_removes_only_the_unmodified_seed_admin_from_an_empty_cloud_database(self) -> None:
        self.assertEqual(self.run_migration(), [])

    def test_preserves_users_when_not_a_clean_cloud_bootstrap(self) -> None:
        scenarios = (
            {"hosting_mode": "self_hosted"},
            {"enabled": False},
            {"organization_count": 1},
            {"user_count": 2},
            {"event_count": 1},
            {"admin_hash": "custom-password-hash"},
            {"full_name": "Changed administrator"},
        )
        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                self.assertEqual(self.run_migration(**scenario)[0], "admin")


if __name__ == "__main__":
    unittest.main()
