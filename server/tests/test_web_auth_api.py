"""Тесты HTTP API для web-auth."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.api.deps_auth import get_auth_service
from app.features.auth import AuthService
from app.main import app
from tests.test_auth_service import AUTH_SECRET, FIXED_NOW, FakeAuthRepository, _user


AUTH_ENDPOINT = "/api/v1/web/auth"


@pytest.fixture()
def auth_client() -> Iterator[TestClient]:
    """TestClient с fake auth service вместо реальной PostgreSQL."""

    repository = FakeAuthRepository([_user()])
    service = AuthService(
        repository=repository,
        auth_secret=AUTH_SECRET,
        session_ttl_hours=12,
        now=FIXED_NOW,
    )

    app.dependency_overrides[get_auth_service] = lambda: service
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


def test_login_sets_http_only_session_cookie(auth_client: TestClient) -> None:
    """Login возвращает user DTO и выставляет HTTP-only cookie."""

    response = auth_client.post(
        f"{AUTH_ENDPOINT}/login",
        json={
            "username": "lab_user",
            "password": "correct-password",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "user": {
            "username": "lab_user",
            "role": "operator",
        }
    }

    set_cookie = response.headers["set-cookie"]
    assert "complex_eeg_session=" in set_cookie
    assert "HttpOnly" in set_cookie
    assert "SameSite=lax" in set_cookie


def test_login_rejects_invalid_credentials(auth_client: TestClient) -> None:
    """Auth error не раскрывает, существует ли username."""

    response = auth_client.post(
        f"{AUTH_ENDPOINT}/login",
        json={
            "username": "lab_user",
            "password": "wrong",
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "auth.invalid_credentials"


def test_me_returns_current_user_after_login(auth_client: TestClient) -> None:
    """GET /me использует cookie, полученную после login."""

    login_response = auth_client.post(
        f"{AUTH_ENDPOINT}/login",
        json={
            "username": "lab_user",
            "password": "correct-password",
        },
    )
    assert login_response.status_code == 200

    response = auth_client.get(f"{AUTH_ENDPOINT}/me")

    assert response.status_code == 200
    assert response.json()["user"]["username"] == "lab_user"


def test_me_requires_session_cookie(auth_client: TestClient) -> None:
    """Без session cookie protected endpoint возвращает 401."""

    response = auth_client.get(f"{AUTH_ENDPOINT}/me")

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "auth.required"


def test_logout_clears_session_cookie(auth_client: TestClient) -> None:
    """Logout отдаёт Set-Cookie, который удаляет session cookie в браузере."""

    login_response = auth_client.post(
        f"{AUTH_ENDPOINT}/login",
        json={
            "username": "lab_user",
            "password": "correct-password",
        },
    )
    assert login_response.status_code == 200

    response = auth_client.post(f"{AUTH_ENDPOINT}/logout")

    assert response.status_code == 200
    assert response.json() == {"status": "logged_out"}
    set_cookie = response.headers["set-cookie"]
    assert "complex_eeg_session=" in set_cookie
    assert "Max-Age=0" in set_cookie
