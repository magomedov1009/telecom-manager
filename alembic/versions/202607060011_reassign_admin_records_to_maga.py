"""Reassign admin records to maga

Revision ID: 202607060011
Revises: 202607060010
Create Date: 2026-07-15
"""
from alembic import op


revision = "202607060011"
down_revision = "202607060010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        DECLARE
            admin_user_id bigint;
            maga_user_id bigint;
        BEGIN
            SELECT id INTO admin_user_id FROM users WHERE username = 'admin' LIMIT 1;
            SELECT id INTO maga_user_id FROM users WHERE username = 'maga' LIMIT 1;

            IF admin_user_id IS NULL OR maga_user_id IS NULL THEN
                RETURN;
            END IF;

            UPDATE connections SET installer_id = maga_user_id WHERE installer_id = admin_user_id;
            UPDATE extra_works SET installer_id = maga_user_id WHERE installer_id = admin_user_id;
            UPDATE expenses SET user_id = maga_user_id WHERE user_id = admin_user_id;
            UPDATE finance_transactions SET user_id = maga_user_id WHERE user_id = admin_user_id;
            UPDATE inventory_transactions SET user_id = maga_user_id WHERE user_id = admin_user_id;
            UPDATE event_logs SET actor_id = maga_user_id WHERE actor_id = admin_user_id;
        END $$;
        """
    )


def downgrade() -> None:
    pass