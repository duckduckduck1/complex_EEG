"""Тесты server-rendered веб-кабинета (страницы Jinja)."""

from __future__ import annotations

import types
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.api.deps_auth import get_auth_service
from app.api.routes_web_experiments import get_web_experiment_service
from app.features.auth import AuthService
from app.main import app
from tests.test_auth_service import AUTH_SECRET, FIXED_NOW, FakeAuthRepository, _user


class _FakeWebExperimentService:
    """Возвращает пустую страницу экспериментов без обращения к PostgreSQL."""

    def list_experiments(self, _filters: object) -> object:
        return types.SimpleNamespace(items=[], limit=50, offset=0, total=0)


@pytest.fixture()
def client() -> Iterator[TestClient]:
    auth_service = AuthService(
        repository=FakeAuthRepository([_user()]),
        auth_secret=AUTH_SECRET,
        session_ttl_hours=12,
        now=FIXED_NOW,
    )
    app.dependency_overrides[get_auth_service] = lambda: auth_service
    app.dependency_overrides[get_web_experiment_service] = _FakeWebExperimentService
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_login_page_renders(client: TestClient) -> None:
    response = client.get("/login")

    assert response.status_code == 200
    assert "Вход" in response.text
    assert '<form method="post" action="/login">' in response.text


def test_root_redirects_to_login_when_anonymous(client: TestClient) -> None:
    response = client.get("/", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"] == "/login"


def test_experiments_requires_login(client: TestClient) -> None:
    response = client.get("/experiments", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"] == "/login"


def test_login_rejects_invalid_credentials(client: TestClient) -> None:
    response = client.post(
        "/login",
        data={"username": "lab_user", "password": "wrong"},
        follow_redirects=False,
    )

    assert response.status_code == 401
    assert "Неверный логин или пароль" in response.text


def test_login_then_view_experiments(client: TestClient) -> None:
    login = client.post(
        "/login",
        data={"username": "lab_user", "password": "correct-password"},
        follow_redirects=False,
    )

    assert login.status_code == 303
    assert login.headers["location"] == "/experiments"
    assert "complex_eeg_session=" in login.headers["set-cookie"]

    page = client.get("/experiments")

    assert page.status_code == 200
    assert "Эксперименты" in page.text
    assert "всего: 0" in page.text
