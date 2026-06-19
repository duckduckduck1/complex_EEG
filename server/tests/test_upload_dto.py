"""Тесты API-safe DTO для upload flow."""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest

from app.features.upload import (
    build_upload_processing_response,
    process_upload_package,
)


VALID_UPLOAD_SESSION_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


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


def test_build_upload_processing_response_for_accepted_package(workspace_tmp_path: Path) -> None:
    """Accepted DTO содержит данные для Web UI без server filesystem paths."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir)

    processing_result = process_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        experiments_root=experiments_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    response = build_upload_processing_response(processing_result)

    assert response.upload_session_id == VALID_UPLOAD_SESSION_ID
    assert response.experiment_id == "exp_01"
    assert response.status == "accepted"
    assert response.accepted is True
    assert response.validation_report_scope == "permanent"
    assert response.signal_size_bytes == 4000
    assert response.sample_count == 1000
    assert response.errors == []
    assert {file.name for file in response.source_files} == {
        "experiment.json",
        "signal.bin",
    }

    serialized = json.dumps(response.model_dump(mode="json"))
    assert str(upload_tmp_root) not in serialized
    assert str(experiments_root) not in serialized


def test_build_upload_processing_response_for_validation_failed_package(
    workspace_tmp_path: Path,
) -> None:
    """Failed DTO возвращает ошибки, но не раскрывает upload_tmp path."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir, include_signal=False)

    processing_result = process_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        experiments_root=experiments_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    response = build_upload_processing_response(processing_result)

    assert response.status == "validation_failed"
    assert response.accepted is False
    assert response.validation_report_scope == "upload_tmp"
    assert response.source_files == []
    assert {error.code for error in response.errors} == {"validation.missing_file"}

    serialized = json.dumps(response.model_dump(mode="json"))
    assert str(upload_tmp_root) not in serialized
    assert str(experiments_root) not in serialized
