from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.models import UserCreate, UserRole
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string


def _headers_for_role(*, client: TestClient, db: Session, role: UserRole) -> dict[str, str]:
    email = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=email, password=password, role=role)
    crud.create_user(session=db, user_create=user_in)
    return user_authentication_headers(client=client, email=email, password=password)


def test_member_cannot_read_users_list(
    client: TestClient, normal_user_token_headers: dict[str, str]
) -> None:
    response = client.get(
        f"{settings.API_V1_STR}/users/",
        headers=normal_user_token_headers,
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "The user doesn't have enough privileges"}


def test_manager_cannot_create_user(client: TestClient, db: Session) -> None:
    manager_headers = _headers_for_role(client=client, db=db, role=UserRole.MANAGER)
    payload = {
        "email": random_email(),
        "password": random_lower_string(),
    }

    response = client.post(
        f"{settings.API_V1_STR}/users/",
        headers=manager_headers,
        json=payload,
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "The user doesn't have enough privileges"}


def test_member_can_read_own_user_by_id(
    client: TestClient, db: Session, normal_user_token_headers: dict[str, str]
) -> None:
    member_user = crud.get_user_by_email(session=db, email=settings.EMAIL_TEST_USER)
    assert member_user

    response = client.get(
        f"{settings.API_V1_STR}/users/{member_user.id}",
        headers=normal_user_token_headers,
    )

    assert response.status_code == 200
    assert response.json()["id"] == str(member_user.id)


def test_admin_and_manager_can_read_metrics(
    client: TestClient,
    db: Session,
    superuser_token_headers: dict[str, str],
) -> None:
    manager_headers = _headers_for_role(client=client, db=db, role=UserRole.MANAGER)

    admin_response = client.get(
        f"{settings.API_V1_STR}/metrics/",
        headers=superuser_token_headers,
    )
    manager_response = client.get(
        f"{settings.API_V1_STR}/metrics/",
        headers=manager_headers,
    )

    assert admin_response.status_code == 200
    assert manager_response.status_code == 200


def test_member_cannot_read_metrics(
    client: TestClient, normal_user_token_headers: dict[str, str]
) -> None:
    response = client.get(
        f"{settings.API_V1_STR}/metrics/",
        headers=normal_user_token_headers,
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "The user doesn't have enough privileges"}
