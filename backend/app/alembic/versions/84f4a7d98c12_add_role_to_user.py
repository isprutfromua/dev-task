"""Add role to user

Revision ID: 84f4a7d98c12
Revises: fe56fa70289e
Create Date: 2026-08-20 00:00:00.000000

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "84f4a7d98c12"
down_revision = "fe56fa70289e"
branch_labels = None
depends_on = None


def upgrade() -> None:
    user_role = sa.Enum("admin", "manager", "member", name="userrole")
    user_role.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "user",
        sa.Column("role", user_role, nullable=False, server_default="member"),
    )
    op.execute("UPDATE \"user\" SET role = 'admin' WHERE is_superuser = true")
    op.alter_column("user", "role", server_default="member")


def downgrade() -> None:
    op.drop_column("user", "role")
    user_role = sa.Enum("admin", "manager", "member", name="userrole")
    user_role.drop(op.get_bind(), checkfirst=True)