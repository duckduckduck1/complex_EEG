"""Тесты health-check endpoint'ов.

Это самый первый smoke test сервера:
если эти тесты падают, приложение даже минимально не работает.
"""

from fastapi.testclient import TestClient

from app.api.routes_health import get_readiness_service
from app.features.readiness import ReadinessCheck, ReadinessReport
from app.main import app

client = TestClient(app)


def test_health() -> None:
    """GET /health должен возвращать статус ok."""

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["service"] == "complex_eeg_server"


class FakeReadinessService:
    """Readiness service для HTTP endpoint tests без реальной PostgreSQL."""

    def __init__(self, report: ReadinessReport) -> None:
        self._report = report

    def check(self) -> ReadinessReport:
        return self._report


def test_ready_returns_ready_report() -> None:
    """GET /ready должен возвращать 200, если все runtime checks успешны."""

    app.dependency_overrides[get_readiness_service] = lambda: FakeReadinessService(
        ReadinessReport(
            status="ready",
            checks=[
                ReadinessCheck(
                    name="postgres",
                    status="ok",
                    message="PostgreSQL connection is available",
                )
            ],
        )
    )

    try:
        response = client.get("/ready")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["status"] == "ready"
    assert response.json()["checks"][0]["name"] == "postgres"


def test_ready_returns_503_when_runtime_check_fails() -> None:
    """GET /ready должен возвращать 503, если runtime dependency недоступна."""

    app.dependency_overrides[get_readiness_service] = lambda: FakeReadinessService(
        ReadinessReport(
            status="not_ready",
            checks=[
                ReadinessCheck(
                    name="postgres",
                    status="failed",
                    message="PostgreSQL check failed",
                )
            ],
        )
    )

    try:
        response = client.get("/ready")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json()["status"] == "not_ready"
    assert response.json()["checks"][0]["status"] == "failed"
