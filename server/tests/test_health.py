"""Тесты health-check endpoint'ов.

Это самый первый smoke test сервера:
если эти тесты падают, приложение даже минимально не работает.
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    """GET /health должен возвращать статус ok."""

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["service"] == "complex_eeg_server"


def test_ready() -> None:
    """GET /ready должен возвращать статус ready."""

    response = client.get("/ready")

    assert response.status_code == 200
    assert response.json()["status"] == "ready"