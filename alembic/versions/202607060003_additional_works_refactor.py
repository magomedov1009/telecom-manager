"""additional works refactor: remove client/title/expenses, work_type_id NOT NULL

Revision ID: 202607060003
Revises: 202607060002
Create Date: 2026-07-08 00:03:00
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "202607060003"
down_revision: str | None = "202607060002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint("extra_works_client_id_fkey", "extra_works", type_="foreignkey")
    op.drop_constraint("extra_works_connection_id_fkey", "extra_works", type_="foreignkey")
    op.drop_column("extra_works", "client_id")
    op.drop_column("extra_works", "connection_id")
    op.drop_column("extra_works", "title")
    op.drop_column("extra_works", "extra_expenses")
    op.alter_column("extra_works", "work_type_id", nullable=False)


def downgrade() -> None:
    op.add_column("extra_works", sa.Column("client_id", sa.BigInteger(), nullable=True))
    op.add_column("extra_works", sa.Column("connection_id", sa.BigInteger(), nullable=True))
    op.add_column("extra_works", sa.Column("title", sa.String(length=255), nullable=True))
    op.add_column("extra_works", sa.Column("extra_expenses", sa.Numeric(precision=14, scale=2), nullable=False, server_default="0"))
    op.alter_column("extra_works", "work_type_id", nullable=True)
    op.create_foreign_key("extra_works_client_id_fkey", "extra_works", "clients", ["client_id"], ["id"], ondelete="CASCADE")
    op.create_foreign_key("extra_works_connection_id_fkey", "extra_works", "connections", ["connection_id"], ["id"], ondelete="SET NULL")
