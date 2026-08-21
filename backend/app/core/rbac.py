from app.models import User, UserRole

FORBIDDEN_DETAIL = "The user doesn't have enough privileges"

USER_MANAGEMENT_ROLES = (UserRole.ADMIN,)
METRICS_READ_ROLES = (UserRole.ADMIN, UserRole.MANAGER)


def has_any_role(user: User, allowed_roles: tuple[UserRole, ...]) -> bool:
    return user.role in allowed_roles


def can_manage_users(user: User) -> bool:
    return has_any_role(user, USER_MANAGEMENT_ROLES)