"""add user manager relation

Revision ID: 202607060010
Revises: 202607060009
Create Date: 2026-07-15
"""

from alembic import op
import sqlalchemy as sa


revision = "202607060010"
down_revision = "202607060009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("manager_id", sa.BigInteger(), nullable=True))
    op.create_index(op.f("ix_users_manager_id"), "users", ["manager_id"], unique=False)
    op.create_foreign_key("fk_users_manager_id_users", "users", "users", ["manager_id"], ["id"], ondelete="SET NULL")


def downgrade() -> None:
    op.drop_constraint("fk_users_manager_id_users", "users", type_="foreignkey")
    op.drop_index(op.f("ix_users_manager_id"), table_name="users")
    op.drop_column("users", "manager_id")
