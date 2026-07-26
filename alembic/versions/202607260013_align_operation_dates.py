"""align financial and inventory operation dates

Revision ID: 202607260013
Revises: 202607250012
Create Date: 2026-07-26
"""

from alembic import op


revision = "202607260013"
down_revision = "202607250012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Financial and inventory totals are filtered by transaction.created_at.
    # Backdated connections previously created transactions at data-entry time,
    # making monthly connection counts disagree with monthly money/materials.
    op.execute(
        """
        UPDATE finance_transactions target_transaction
        SET created_at = connection.connection_date::timestamp
        FROM connections connection
        WHERE target_transaction.connection_id = connection.id;
        """
    )
    op.execute(
        """
        UPDATE inventory_transactions target_transaction
        SET created_at = connection.connection_date::timestamp
        FROM connections connection
        WHERE target_transaction.connection_id = connection.id;
        """
    )
    op.execute(
        """
        UPDATE finance_transactions target_transaction
        SET created_at = work.work_date::timestamp
        FROM extra_works work
        WHERE target_transaction.extra_work_id = work.id;
        """
    )
    op.execute(
        """
        UPDATE inventory_transactions target_transaction
        SET created_at = work.work_date::timestamp
        FROM extra_works work
        WHERE target_transaction.operation_type = 'WRITE_OFF'
          AND target_transaction.comment = 'Допработа #' || work.id::text;
        """
    )


def downgrade() -> None:
    # Original data-entry timestamps cannot be reconstructed after alignment.
    pass
