"""Тесты HTTP API для upload sessions."""

from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api.routes_upload_sessions import get_upload_session_service
from app.db.models import UploadSession
from app.features.upload.session_service import UploadSessionService
from app.main import app
from tests.test_upload_session_service import (
    FIXED_NOW,
    FakeUploadSessionRepository,
    _service,
)


client = TestClient(app)
UPLOAD_SESSIONS_ENDPOINT = "/api/v1/uploads"
VALID_UPLOAD_SESSION_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


@pytest.fixture()
def upload_session_service(workspace_tmp_path: Path) -> Iterator[UploadSessionService]:
    """Подменяет FastAPI dependency настоящего DB service на in-memory service."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)

    app.dependency_overrides[get_upload_session_service] = lambda: service
    yield service
    app.dependency_overrides.clear()


def test_create_upload_session_returns_session_contract(
    upload_session_service: UploadSessionService,
) -> None:
    """POST /api/v1/uploads создаёт session и возвращает публичный контракт."""

    response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={
            "experiment_id": "exp_01",
            "display_name": "Experiment 01",
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["experiment_id"] == "exp_01"
    assert body["status"] == "uploading"
    assert body["upload_base_url"] == f"/api/v1/uploads/{body['upload_session_id']}"
    assert body["expires_at"] == "2026-06-21T12:00:00+00:00"
    assert "tmp_path" not in body


def test_create_upload_session_rejects_expected_files_without_required_file(
    upload_session_service: UploadSessionService,
) -> None:
    """API возвращает machine-readable ошибку, если payload нарушает upload contract."""

    response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={
            "experiment_id": "exp_01",
            "expected_files": ["experiment.json"],
        },
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "request.invalid_payload"


def test_create_upload_session_rejects_invalid_experiment_id(
    upload_session_service: UploadSessionService,
) -> None:
    """Некорректный experiment_id тоже возвращает стабильный error_code."""

    response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={"experiment_id": "../bad"},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "request.invalid_payload"


def test_create_upload_session_rejects_second_active_session(
    upload_session_service: UploadSessionService,
) -> None:
    """Один experiment_id не может иметь две активные upload sessions."""

    first_response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={"experiment_id": "exp_01"},
    )
    assert first_response.status_code == 201

    second_response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={"experiment_id": "exp_01"},
    )

    assert second_response.status_code == 409
    assert second_response.json()["detail"]["code"] == "upload.session_already_active"


def test_get_upload_session_returns_status(
    upload_session_service: UploadSessionService,
) -> None:
    """GET /api/v1/uploads/{id} возвращает status DTO."""

    create_response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={"experiment_id": "exp_01"},
    )
    upload_session_id = create_response.json()["upload_session_id"]

    response = client.get(f"{UPLOAD_SESSIONS_ENDPOINT}/{upload_session_id}")

    assert response.status_code == 200
    body = response.json()
    assert body["upload_session_id"] == upload_session_id
    assert body["experiment_id"] == "exp_01"
    assert body["status"] == "uploading"
    assert body["uploaded_files"] == []
    assert "signal.bin" in body["expected_files"]
    assert "tmp_path" not in body


def test_get_upload_session_returns_404_for_unknown_session(
    upload_session_service: UploadSessionService,
) -> None:
    """Неизвестная session превращается в стабильный API error_code."""

    response = client.get(f"{UPLOAD_SESSIONS_ENDPOINT}/{VALID_UPLOAD_SESSION_ID}")

    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "upload.session_not_found"


def test_cancel_upload_session_returns_cancelled_status(
    upload_session_service: UploadSessionService,
) -> None:
    """DELETE /api/v1/uploads/{id} отменяет активную session."""

    create_response = client.post(
        UPLOAD_SESSIONS_ENDPOINT,
        json={"experiment_id": "exp_01"},
    )
    upload_session_id = create_response.json()["upload_session_id"]

    response = client.delete(f"{UPLOAD_SESSIONS_ENDPOINT}/{upload_session_id}")

    assert response.status_code == 200
    assert response.json()["status"] == "cancelled"


def test_cancel_upload_session_returns_409_for_final_status(
    upload_session_service: UploadSessionService,
) -> None:
    """Final status нельзя отменять, если это не already-cancelled."""

    upload_session_service._repository.upload_sessions[VALID_UPLOAD_SESSION_ID] = UploadSession(
        id=VALID_UPLOAD_SESSION_ID,
        experiment_id="exp_01",
        status="accepted",
        tmp_path="/tmp/upload",
        client_id="web_ui",
        expected_files={"files": ["signal.bin", "experiment.json"]},
        uploaded_files={"files": []},
        expires_at=FIXED_NOW,
    )

    response = client.delete(f"{UPLOAD_SESSIONS_ENDPOINT}/{VALID_UPLOAD_SESSION_ID}")

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "upload.session_state_conflict"
