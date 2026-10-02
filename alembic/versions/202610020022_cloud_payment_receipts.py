"""record each successful YooMoney charge for a checkout

Revision ID: 202610020022
Revises: 202610010021
Create Date: 2026-10-02
"""

from alembic import op
import sqlalchemy as sa


revision = "202610020022"
down_revision = "202610010021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "cloud_payment_receipts",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("payment_id", sa.BigInteger(), nullable=False),
        sa.Column("provider_operation_id", sa.String(length=255), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["payment_id"], ["cloud_payments.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("provider_operation_id"),
    )
    op.create_index(
        "ix_cloud_payment_receipts_payment_id",
        "cloud_payment_receipts",
        ["payment_id"],
    )
    # Preserve the successful transactions already accepted before receipt
    # tracking was introduced. Orders without a verified operation are omitted.
    op.execute(
        sa.text(
            """
            INSERT INTO cloud_payment_receipts
                (payment_id, provider_operation_id, amount, paid_at, created_at, updated_at)
            SELECT id, provider_operation_id, amount, paid_at, created_at, updated_at
            FROM cloud_payments
            WHERE status = 'paid'
              AND provider_operation_id IS NOT NULL
              AND paid_at IS NOT NULL
            """
        )
    )


def downgrade() -> None:
    op.drop_table("cloud_payment_receipts")
