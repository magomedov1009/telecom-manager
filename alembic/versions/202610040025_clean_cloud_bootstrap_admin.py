"""Remove the inaccessible demo administrator from a clean cloud install.

Revision ID: 202610040025
Revises: 202610040024
Create Date: 2026-10-02
"""

from alembic import op
import sqlalchemy as sa

from app.core.config import settings


revision = "202610040025"
down_revision = "202610040024"
branch_labels = None
depends_on = None


_SEEDED_ADMIN_HASH = (
    "pbkdf2_sha256$260000$telecom-manager-admin$"
    "ef202caeadca3d4d6d0224f5b28877578636576ce1647176065a45416c264a80"
)
_USER_ACTIVITY_TABLES = {
    "connections": "installer_id",
    "extra_works": "installer_id",
    "expenses": "user_id",
    "finance_transactions": "user_id",
    "inventory_transactions": "user_id",
    "event_logs": "actor_id",
}


def upgrade() -> None:
    if (
        settings.hosting_mode != "cloud"
        or not settings.bootstrap_clean_cloud_defaults
    ):
        return

    connection = op.get_bind()
    # This flag is intended only for the first migration of a new cloud
    # database. Any tenant is sufficient reason to preserve all users.
    if connection.scalar(sa.text("SELECT COUNT(*) FROM mobile_organizations")):
        return
    if connection.scalar(sa.text("SELECT COUNT(*) FROM users")) != 1:
        return

    seeded_admin_id = connection.scalar(
        sa.text(
            """
            SELECT id FROM users
            WHERE username = 'admin'
              AND full_name = 'Administrator'
              AND hashed_password = :password_hash
              AND role = 'ADMIN'
              AND is_active IS TRUE
              AND last_login_at IS NULL
              AND phone IS NULL
              AND email IS NULL
              AND cloud_trial_used IS FALSE
              AND comment IS NULL
              AND manager_id IS NULL
            """
        ).bindparams(password_hash=_SEEDED_ADMIN_HASH)
    )
    if seeded_admin_id is None:
        return

    # Do not delete an account that has ever been associated with operational
    # activity, even if its password still matches the historical demo hash.
    for table, column in _USER_ACTIVITY_TABLES.items():
        if connection.scalar(
            sa.text(
                f"SELECT EXISTS (SELECT 1 FROM {table} WHERE {column} = :user_id)"
            ).bindparams(user_id=seeded_admin_id)
        ):
            return

    connection.execute(
        sa.text("DELETE FROM users WHERE id = :user_id").bindparams(
            user_id=seeded_admin_id
        )
    )


def downgrade() -> None:
    # Never recreate a user or credential on downgrade.
    pass
