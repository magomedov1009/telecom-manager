"""add manager role and user comments

Revision ID: 202607060009
Revises: 202607060008
Create Date: 2026-07-09
"""

from alembic import op


revision = "202607060009"
down_revision = "202607060008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'MANAGER'")
    op.execute("UPDATE users SET role = 'MANAGER' WHERE role = 'OFFICE'")
    op.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS comment VARCHAR(500)')


def downgrade() -> None:
    op.execute("UPDATE users SET role = 'OFFICE' WHERE role = 'MANAGER'")
    op.execute('ALTER TABLE users DROP COLUMN IF EXISTS comment')
