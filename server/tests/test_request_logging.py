"""Тесты HTTP request logging middleware."""

from __future__ import annotations

import json
import logging

from fastapi.testclient import TestClient

from app.core.logging import REQUEST_LOGGER_NAME
from app.main import app


client = TestClient(app)


def _request_log_events(caplog) -> list[dict[str, object]]:
    events = []

    for record in caplog.records:
        if record.name != REQUEST_LOGGER_NAME:
            continue

        events.append(json.loads(record.getMessage()))

    return events


def test_request_logging_reuses_incoming_request_id(caplog) -> None:
    """Middleware пишет JSON-log и возвращает входящий request id."""

    caplog.set_level(logging.INFO, logger=REQUEST_LOGGER_NAME)

    response = client.get(
        "/health",
        headers={
            "X-Request-ID": "req-test-123",
            "User-Agent": "pytest",
        },
    )

    assert response.status_code == 200
    assert response.headers["X-Request-ID"] == "req-test-123"

    event = _request_log_events(caplog)[-1]
    assert event["event"] == "http_request"
    assert event["request_id"] == "req-test-123"
    assert event["method"] == "GET"
    assert event["path"] == "/health"
    assert event["status_code"] == 200
    assert event["user_agent"] == "pytest"
    assert isinstance(event["duration_ms"], float)


def test_request_logging_generates_request_id_when_header_is_missing(caplog) -> None:
    """Если request id не пришёл от клиента, сервер создаёт новый."""

    caplog.set_level(logging.INFO, logger=REQUEST_LOGGER_NAME)

    response = client.get("/health")

    generated_request_id = response.headers["X-Request-ID"]
    assert generated_request_id

    event = _request_log_events(caplog)[-1]
    assert event["request_id"] == generated_request_id


def test_request_logging_omits_query_string_from_path(caplog) -> None:
    """В лог пишем path без query string, чтобы не утаскивать секреты из URL."""

    caplog.set_level(logging.INFO, logger=REQUEST_LOGGER_NAME)

    response = client.get("/health?token=secret")

    assert response.status_code == 200

    event = _request_log_events(caplog)[-1]
    assert event["path"] == "/health"
    assert "secret" not in json.dumps(event)
