"""drop legacy extra works client columns

Revision ID: 202607060007
Revises: 202607060006
Create Date: 2026-07-09
"""

from alembic import op


revision = "202607060007"
down_revision = "202607060006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute('ALTER TABLE extra_works DROP CONSTRAINT IF EXISTS extra_works_client_id_fkey')
    op.execute('ALTER TABLE extra_works DROP CONSTRAINT IF EXISTS extra_works_connection_id_fkey')
    op.execute('DROP INDEX IF EXISTS ix_extra_works_client_id')
    op.execute('DROP INDEX IF EXISTS ix_extra_works_connection_id')
    op.execute('ALTER TABLE extra_works DROP COLUMN IF EXISTS client_id')
    op.execute('ALTER TABLE extra_works DROP COLUMN IF EXISTS connection_id')


def downgrade() -> None:
    op.execute('ALTER TABLE extra_works ADD COLUMN IF NOT EXISTS client_id BIGINT')
    op.execute('ALTER TABLE extra_works ADD COLUMN IF NOT EXISTS connection_id BIGINT')
    op.execute('CREATE INDEX IF NOT EXISTS ix_extra_works_client_id ON extra_works (client_id)')
    op.execute('CREATE INDEX IF NOT EXISTS ix_extra_works_connection_id ON extra_works (connection_id)')
    op.execute('ALTER TABLE extra_works ADD CONSTRAINT extra_works_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE')
    op.execute('ALTER TABLE extra_works ADD CONSTRAINT extra_works_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES connections(id) ON DELETE SET NULL')
