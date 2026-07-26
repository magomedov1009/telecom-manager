"""mobile synchronization storage

Revision ID: 202607260014
Revises: 202607260013
"""

from alembic import op
import sqlalchemy as sa

revision = "202607260014"
down_revision = "202607260013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table("mobile_organizations", sa.Column("name", sa.String(255), nullable=False), sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))
    op.create_table("mobile_memberships", sa.Column("organization_id", sa.BigInteger(), sa.ForeignKey("mobile_organizations.id", ondelete="CASCADE"), nullable=False), sa.Column("user_id", sa.BigInteger(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False), sa.Column("role", sa.String(32), nullable=False), sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.UniqueConstraint("organization_id", "user_id"))
    op.create_table("mobile_device_tokens", sa.Column("token_hash", sa.String(64), nullable=False, unique=True), sa.Column("organization_id", sa.BigInteger(), sa.ForeignKey("mobile_organizations.id", ondelete="CASCADE"), nullable=False), sa.Column("user_id", sa.BigInteger(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False), sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))
    op.create_table("mobile_sync_records", sa.Column("organization_id", sa.BigInteger(), sa.ForeignKey("mobile_organizations.id", ondelete="CASCADE"), nullable=False), sa.Column("entity_type", sa.String(64), nullable=False), sa.Column("entity_id", sa.String(36), nullable=False), sa.Column("payload", sa.JSON(), nullable=False), sa.Column("version", sa.Integer(), nullable=False, server_default="1"), sa.Column("deleted_at", sa.DateTime(timezone=True)), sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.UniqueConstraint("organization_id", "entity_type", "entity_id"))
    op.create_table("mobile_sync_changes", sa.Column("organization_id", sa.BigInteger(), sa.ForeignKey("mobile_organizations.id", ondelete="CASCADE"), nullable=False), sa.Column("record_id", sa.BigInteger(), sa.ForeignKey("mobile_sync_records.id", ondelete="CASCADE"), nullable=False), sa.Column("entity_type", sa.String(64), nullable=False), sa.Column("entity_id", sa.String(36), nullable=False), sa.Column("operation", sa.String(16), nullable=False), sa.Column("version", sa.Integer(), nullable=False), sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))


def downgrade() -> None:
    op.drop_table("mobile_sync_changes")
    op.drop_table("mobile_sync_records")
    op.drop_table("mobile_device_tokens")
    op.drop_table("mobile_memberships")
    op.drop_table("mobile_organizations")
