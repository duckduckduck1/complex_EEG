"""Тесты dev/test API endpoint'а для upload flow."""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app


client = TestClient(app)
VALID_UPLOAD_SESSION_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"
UPLOAD_ENDPOINT = "/api/v1/dev/uploads/process-local-folder"


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


def _enable_local_upload_endpoint(
    monkeypatch: pytest.MonkeyPatch,
    workspace_tmp_path: Path,
) -> tuple[Path, Path]:
    """Включает dev/test endpoint и возвращает корни upload_tmp/experiments."""

    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"

    monkeypatch.setattr(settings, "app_env", "test")
    monkeypatch.setattr(settings, "enable_local_upload_endpoint", True)
    monkeypatch.setattr(settings, "upload_tmp_dir", str(upload_tmp_root))
    monkeypatch.setattr(settings, "experiments_dir", str(experiments_root))

    return upload_tmp_root, experiments_root


def _write_package(
    package_dir: Path,
    *,
    experiment_id: str = "exp_01",
    signal_samples: int = 1000,
    include_signal: bool = True,
) -> None:
    package_dir.mkdir()

    if include_signal:
        (package_dir / "signal.bin").write_bytes(b"\x00\x00\x00\x00" * signal_samples)

    experiment_json: dict[str, Any] = {
        "experiment_id": experiment_id,
        "metadata": {"animal_id": "mouse_1"},
        "segments": [
            {
                "segment_id": "seg_1",
                "start_sample": 0,
                "end_sample": signal_samples,
            }
        ],
        "labels": [],
        "fbm_events": [],
    }
    (package_dir / "experiment.json").write_text(
        json.dumps(experiment_json),
        encoding="utf-8",
    )


def test_process_local_folder_upload_is_disabled_by_default(workspace_tmp_path: Path) -> None:
    """Dev/test endpoint не должен работать без явного config-флага."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    _write_package(source_package_dir)

    response = client.post(
        UPLOAD_ENDPOINT,
        json={
            "source_package_dir": str(source_package_dir),
            "upload_session_id": VALID_UPLOAD_SESSION_ID,
            "experiment_id": "exp_01",
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "upload.local_endpoint_disabled"


def test_process_local_folder_upload_accepts_valid_package(
    monkeypatch: pytest.MonkeyPatch,
    workspace_tmp_path: Path,
) -> None:
    """Валидный пакет проходит API bridge и возвращает API-safe DTO."""

    upload_tmp_root, experiments_root = _enable_local_upload_endpoint(
        monkeypatch,
        workspace_tmp_path,
    )
    source_package_dir = workspace_tmp_path / "incoming_exp"
    _write_package(source_package_dir)

    response = client.post(
        UPLOAD_ENDPOINT,
        json={
            "source_package_dir": str(source_package_dir),
            "upload_session_id": VALID_UPLOAD_SESSION_ID,
            "experiment_id": "exp_01",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "accepted"
    assert body["accepted"] is True
    assert body["experiment_id"] == "exp_01"
    assert body["validation_report_scope"] == "permanent"
    assert {file["name"] for file in body["source_files"]} == {
        "experiment.json",
        "signal.bin",
    }

    serialized = json.dumps(body)
    assert str(upload_tmp_root) not in serialized
    assert str(experiments_root) not in serialized


def test_process_local_folder_upload_returns_validation_failed(
    monkeypatch: pytest.MonkeyPatch,
    workspace_tmp_path: Path,
) -> None:
    """Невалидный пакет возвращает 200 с validation_failed DTO и errors."""

    _enable_local_upload_endpoint(monkeypatch, workspace_tmp_path)
    source_package_dir = workspace_tmp_path / "incoming_exp"
    _write_package(source_package_dir, include_signal=False)

    response = client.post(
        UPLOAD_ENDPOINT,
        json={
            "source_package_dir": str(source_package_dir),
            "upload_session_id": VALID_UPLOAD_SESSION_ID,
            "experiment_id": "exp_01",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "validation_failed"
    assert body["accepted"] is False
    assert body["validation_report_scope"] == "upload_tmp"
    assert {error["code"] for error in body["errors"]} == {"validation.missing_file"}


def test_process_local_folder_upload_returns_conflict_for_existing_experiment(
    monkeypatch: pytest.MonkeyPatch,
    workspace_tmp_path: Path,
) -> None:
    """Если experiment_id уже есть в permanent storage, API возвращает 409."""

    _, experiments_root = _enable_local_upload_endpoint(monkeypatch, workspace_tmp_path)
    source_package_dir = workspace_tmp_path / "incoming_exp"
    _write_package(source_package_dir)
    (experiments_root / "exp_01").mkdir(parents=True)

    response = client.post(
        UPLOAD_ENDPOINT,
        json={
            "source_package_dir": str(source_package_dir),
            "upload_session_id": VALID_UPLOAD_SESSION_ID,
            "experiment_id": "exp_01",
        },
    )

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "upload.promotion_failed"
