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
    """Возвращает фиксированные данные экспериментов без обращения к PostgreSQL."""

    def list_experiments(self, _filters: object) -> object:
        return types.SimpleNamespace(items=[], limit=50, offset=0, total=0)

    def get_experiment_detail(self, experiment_id: str) -> object:
        return types.SimpleNamespace(
            experiment_id=experiment_id,
            display_name=experiment_id,
            status="accepted",
            metadata={"animal_id": "mouse_1"},
            uploaded_at=FIXED_NOW,
            accepted_at=FIXED_NOW,
            updated_at=FIXED_NOW,
            validation=types.SimpleNamespace(status="accepted", error=None),
            source_files=[
                types.SimpleNamespace(name="signal.bin", size_bytes=4000, download_allowed=False)
            ],
            pipeline_runs=[
                types.SimpleNamespace(
                    pipeline_run_id="01RUN",
                    status="queued",
                    trigger_type="auto_primary",
                    pipeline_version="dev",
                    started_at=None,
                    finished_at=None,
                    error_code=None,
                    error_message=None,
                    artifacts=[
                        types.SimpleNamespace(
                            artifact_id="01ART",
                            name="report.json",
                            kind="report",
                            size_bytes=120,
                            media_type="application/json",
                        )
                    ],
                )
            ],
            events=[
                types.SimpleNamespace(
                    event_type="pipeline_primary_queued",
                    from_status="accepted",
                    to_status="accepted",
                    message="Primary pipeline run queued",
                    created_at=FIXED_NOW,
                )
            ],
        )


@pytest.fixture()
def client() -> Iterator[TestClient]:
    yield from _client_for_role("operator")


@pytest.fixture()
def viewer_client() -> Iterator[TestClient]:
    yield from _client_for_role("viewer")


def _client_for_role(role: str) -> Iterator[TestClient]:
    user = _user()
    user.role = role
    auth_service = AuthService(
        repository=FakeAuthRepository([user]),
        auth_secret=AUTH_SECRET,
        session_ttl_hours=12,
        now=FIXED_NOW,
    )
    app.dependency_overrides[get_auth_service] = lambda: auth_service
    app.dependency_overrides[get_web_experiment_service] = _FakeWebExperimentService
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _login(test_client: TestClient) -> None:
    response = test_client.post(
        "/login",
        data={"username": "lab_user", "password": "correct-password"},
        follow_redirects=False,
    )
    assert response.status_code == 303


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
    assert 'href="/uploads/new"' in page.text


def test_upload_page_requires_login(client: TestClient) -> None:
    response = client.get("/uploads/new", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"] == "/login"


def test_operator_can_open_upload_page(client: TestClient) -> None:
    _login(client)

    response = client.get("/uploads/new")

    assert response.status_code == 200
    assert "Загрузка эксперимента" in response.text
    assert "data-upload-form" in response.text
    assert "data-csrf-token=" in response.text
    assert "signal.bin,experiment.json" in response.text
    assert "webkitdirectory" in response.text
    assert 'src="/static/upload.js"' in response.text


def test_viewer_cannot_open_upload_page(viewer_client: TestClient) -> None:
    _login(viewer_client)

    response = viewer_client.get("/uploads/new")

    assert response.status_code == 403
    assert "Недостаточно прав" in response.text


def test_viewer_does_not_see_upload_link(viewer_client: TestClient) -> None:
    _login(viewer_client)

    response = viewer_client.get("/experiments")

    assert response.status_code == 200
    assert 'href="/uploads/new"' not in response.text


def test_detail_page_requires_login(client: TestClient) -> None:
    response = client.get("/experiments/exp_01", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"] == "/login"


def test_detail_page_shows_runs_artifacts_and_events(client: TestClient) -> None:
    _login(client)

    response = client.get("/experiments/exp_01")

    assert response.status_code == 200
    assert "Обработка" in response.text
    assert "auto_primary" in response.text
    assert "/api/v1/web/experiments/exp_01/artifacts/01ART" in response.text
    assert "report.json" in response.text
    assert "События" in response.text
    assert "pipeline_primary_queued" in response.text


def test_experiments_filters_round_trip(client: TestClient) -> None:
    _login(client)

    response = client.get("/experiments?search=mouse&status=accepted&sort=display_name_asc")

    assert response.status_code == 200
    assert 'value="mouse"' in response.text
    assert '<option value="accepted" selected>' in response.text
    assert '<option value="display_name_asc" selected>' in response.text
    assert "Ничего не найдено по фильтрам" in response.text


class _PaginatedFakeWebExperimentService:
    """Фейк с total больше размера страницы — для проверки пагинации."""

    def list_experiments(self, filters: object) -> object:
        total = 45
        items = [
            types.SimpleNamespace(
                experiment_id=f"exp_{index:02d}",
                display_name=f"exp_{index:02d}",
                status="accepted",
                uploaded_at=FIXED_NOW,
                last_pipeline_status=None,
                last_error=None,
            )
            for index in range(filters.offset, min(filters.offset + filters.limit, total))
        ]
        return types.SimpleNamespace(
            items=items, limit=filters.limit, offset=filters.offset, total=total
        )


def test_experiments_pagination(client: TestClient) -> None:
    _login(client)
    app.dependency_overrides[get_web_experiment_service] = _PaginatedFakeWebExperimentService

    first = client.get("/experiments")
    assert first.status_code == 200
    assert "показано 1-20 из 45" in first.text
    assert "Вперёд" in first.text
    assert "Назад" not in first.text

    last = client.get("/experiments?page=3")
    assert last.status_code == 200
    assert "показано 41-45 из 45" in last.text
    assert "Назад" in last.text
    assert "Вперёд" not in last.text
