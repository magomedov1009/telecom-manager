"""limit the free cloud trial to one per owner account

Revision ID: 202610040024
Revises: 202610030023
Create Date: 2026-10-04
"""

from alembic import op
import sqlalchemy as sa


revision = "202610040024"
down_revision = "202610030023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "cloud_trial_used",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    # Existing cloud organizations already received a trial under the former
    # per-organization policy; preserve that history at account scope.
    op.execute(
        sa.text(
            """
            UPDATE users
            SET cloud_trial_used = TRUE
            WHERE id IN (
                SELECT DISTINCT owner_user_id
                FROM mobile_organizations
                WHERE owner_user_id IS NOT NULL
                  AND hosting_mode = 'cloud'
                  AND is_legacy_workspace = FALSE
            )
            """
        )
    )


def downgrade() -> None:
    op.drop_column("users", "cloud_trial_used")
