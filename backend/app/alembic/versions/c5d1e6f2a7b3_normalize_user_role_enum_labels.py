"""Normalize user role enum labels

Revision ID: c5d1e6f2a7b3
Revises: 84f4a7d98c12
Create Date: 2026-08-20 00:00:01.000000

"""

from alembic import op


# revision identifiers, used by Alembic.
revision = "c5d1e6f2a7b3"
down_revision = "84f4a7d98c12"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # SQLAlchemy persists Python enum member names (e.g. ``ADMIN``). The
    # preceding migration introduced lowercase PostgreSQL labels, so rename
    # them to keep the database and application representations consistent.
    for old, new in (("admin", "ADMIN"), ("manager", "MANAGER"), ("member", "MEMBER")):
        op.execute(f"ALTER TYPE userrole RENAME VALUE '{old}' TO '{new}'")


def downgrade() -> None:
    for old, new in (("ADMIN", "admin"), ("MANAGER", "manager"), ("MEMBER", "member")):
        op.execute(f"ALTER TYPE userrole RENAME VALUE '{old}' TO '{new}'")
