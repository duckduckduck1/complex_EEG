"""Тесты полного файлового upload flow без БД."""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest

from app.features.upload import (
    UploadPromotionError,
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


def test_process_upload_package_accepts_valid_package(workspace_tmp_path: Path) -> None:
    """Валидный пакет проходит staging, validation report и promotion."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir)

    result = process_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        experiments_root=experiments_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    assert result.is_accepted is True
    assert result.status == "accepted"
    assert result.promotion_result is not None
    assert result.validation_report_path == (
        experiments_root / "exp_01" / "validation" / "validation_report.json"
    )
    assert (experiments_root / "exp_01" / "source" / "signal.bin").exists()
    assert (experiments_root / "exp_01" / "source" / "experiment.json").exists()

    report = json.loads(result.validation_report_path.read_text(encoding="utf-8"))
    assert report["status"] == "accepted"
    assert report["experiment_id"] == "exp_01"


def test_process_upload_package_keeps_invalid_package_in_upload_tmp(workspace_tmp_path: Path) -> None:
    """Невалидный пакет получает report, но не переносится в permanent storage."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir, include_signal=False)

    result = process_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        experiments_root=experiments_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    assert result.is_accepted is False
    assert result.status == "validation_failed"
    assert result.promotion_result is None
    assert result.validation_report_path == (
        upload_tmp_root / VALID_UPLOAD_SESSION_ID / "validation_report.json"
    )
    assert not (experiments_root / "exp_01").exists()

    report = json.loads(result.validation_report_path.read_text(encoding="utf-8"))
    error_codes = {error["code"] for error in report["errors"]}
    assert report["status"] == "validation_failed"
    assert "validation.missing_file" in error_codes


def test_process_upload_package_does_not_overwrite_existing_experiment(workspace_tmp_path: Path) -> None:
    """Orchestration не должен перезаписывать уже существующий experiment_id."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir)
    (experiments_root / "exp_01").mkdir(parents=True)

    with pytest.raises(UploadPromotionError):
        process_upload_package(
            source_package_dir=source_package_dir,
            upload_tmp_root=upload_tmp_root,
            experiments_root=experiments_root,
            upload_session_id=VALID_UPLOAD_SESSION_ID,
            expected_experiment_id="exp_01",
        )
