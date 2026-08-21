from sqlmodel import Session, create_engine, select

from app import crud
from app.core.config import settings
from app.models import User, UserCreate, UserRole

engine = create_engine(str(settings.DATABASE_URL))


# make sure all SQLModel models are imported (app.models) before initializing DB
# otherwise, SQLModel might fail to initialize relationships properly
# for more details: https://github.com/fastapi/full-stack-fastapi-template/issues/28


def init_db(session: Session) -> None:
    # Tables should be created with Alembic migrations
    # But if you don't want to use migrations, create
    # the tables un-commenting the next lines
    # from sqlmodel import SQLModel

    # This works because the models are already imported and registered from app.models
    # SQLModel.metadata.create_all(engine)

    user = session.exec(
        select(User).where(User.email == settings.FIRST_SUPERUSER)
    ).first()
    if not user:
        user_in = UserCreate(
            email=settings.FIRST_SUPERUSER,
            password=settings.FIRST_SUPERUSER_PASSWORD,
            is_superuser=True,
            role=UserRole.ADMIN,
        )
        crud.create_user(session=session, user_create=user_in)

    role_seed_users = [
        (
            settings.FIRST_SUPERUSER,
            settings.FIRST_SUPERUSER_PASSWORD,
            UserRole.ADMIN,
            True,
            "Admin User",
        ),
        (
            "manager@example.com",
            "managerpassword",
            UserRole.MANAGER,
            False,
            "Manager User",
        ),
        (
            settings.EMAIL_TEST_USER,
            "memberpassword",
            UserRole.MEMBER,
            False,
            "Member User",
        ),
    ]

    for email, password, role, is_superuser, full_name in role_seed_users:
        role_user = session.exec(select(User).where(User.email == email)).first()
        if not role_user:
            role_user_in = UserCreate(
                email=email,
                password=password,
                role=role,
                is_superuser=is_superuser,
                full_name=full_name,
            )
            crud.create_user(session=session, user_create=role_user_in)
            continue

        updated = False
        if role_user.role != role:
            role_user.role = role
            updated = True
        if role_user.is_superuser != is_superuser:
            role_user.is_superuser = is_superuser
            updated = True
        if updated:
            session.add(role_user)
            session.commit()
