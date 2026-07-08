"""drop legacy clients provider column

Revision ID: 202607060006
Revises: 202607060005
Create Date: 2026-07-09
"""

from alembic import op


revision = "202607060006"
down_revision = "202607060005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute('DROP INDEX IF EXISTS ix_clients_provider')
    op.execute('ALTER TABLE clients DROP COLUMN IF EXISTS provider')


def downgrade() -> None:
    op.execute("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'provider') THEN CREATE TYPE provider AS ENUM ('ELLKO', 'OPTIMASET'); END IF; END $$")
    op.execute('ALTER TABLE clients ADD COLUMN IF NOT EXISTS provider provider')
    op.execute("UPDATE clients SET provider = providers.name::provider FROM providers WHERE providers.id = clients.provider_id AND providers.name IN ('ELLKO', 'OPTIMASET') AND clients.provider IS NULL")
    op.execute("UPDATE clients SET provider = 'ELLKO'::provider WHERE provider IS NULL")
    op.execute('ALTER TABLE clients ALTER COLUMN provider SET NOT NULL')
    op.execute('CREATE INDEX IF NOT EXISTS ix_clients_provider ON clients (provider)')
