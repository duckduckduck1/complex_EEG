"""Тесты файловой подготовки upload-сессии."""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest

from app.features.upload import (
    UploadStagingError,
    build_upload_session_dir,
    stage_upload_package,
)


VALID_UPLOAD_SESSION_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория.

    В текущей Windows-среде системный temp может быть недоступен из-за прав,
    поэтому тесты используют локальную `.test_tmp`.
    """

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


def _write_package(
    package_dir: Path,
    *,
    experiment_id: str = "exp_01",
    signal_samples: int = 1000,
    include_signal: bool = True,
    extra_files: dict[str, str] | None = None,
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

    for file_name, content in (extra_files or {}).items():
        (package_dir / file_name).write_text(content, encoding="utf-8")


def test_build_upload_session_dir_rejects_path_traversal() -> None:
    """ID с разделителями пути не должен превращаться в filesystem path."""

    with pytest.raises(UploadStagingError):
        build_upload_session_dir("/tmp/upload", "../bad")


def test_stage_upload_package_accepts_valid_package(workspace_tmp_path: Path) -> None:
    """Валидный пакет копируется в upload_tmp и получает accepted report."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    _write_package(source_package_dir)

    result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    assert result.is_valid is True
    assert result.session_dir == upload_tmp_root / VALID_UPLOAD_SESSION_ID
    assert result.package_dir == result.session_dir / "source"
    assert result.validation_report_path == result.session_dir / "validation_report.json"
    assert (result.package_dir / "signal.bin").exists()
    assert (result.package_dir / "experiment.json").exists()

    report = json.loads(result.validation_report_path.read_text(encoding="utf-8"))
    assert report["status"] == "accepted"
    assert report["experiment_id"] == "exp_01"


def test_stage_upload_package_writes_failed_report(workspace_tmp_path: Path) -> None:
    """Даже невалидный пакет получает validation_report.json для диагностики."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    _write_package(source_package_dir, include_signal=False)

    result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    assert result.is_valid is False
    assert result.validation_report_path.exists()

    report = json.loads(result.validation_report_path.read_text(encoding="utf-8"))
    error_codes = {error["code"] for error in report["errors"]}
    assert report["status"] == "validation_failed"
    assert "validation.missing_file" in error_codes


def test_stage_upload_package_rejects_existing_session_dir(workspace_tmp_path: Path) -> None:
    """Повторное использование upload_session_id запрещено на файловом уровне."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    existing_session_dir = upload_tmp_root / VALID_UPLOAD_SESSION_ID
    _write_package(source_package_dir)
    existing_session_dir.mkdir(parents=True)

    with pytest.raises(UploadStagingError):
        stage_upload_package(
            source_package_dir=source_package_dir,
            upload_tmp_root=upload_tmp_root,
            upload_session_id=VALID_UPLOAD_SESSION_ID,
            expected_experiment_id="exp_01",
        )


def test_stage_upload_package_copies_only_contract_files(workspace_tmp_path: Path) -> None:
    """Лишние файлы из выбранной пользователем папки не попадают в upload_tmp."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    _write_package(
        source_package_dir,
        extra_files={
            "journal.ndjson": '{"type":"experiment_started"}',
            "app.log": "application diagnostics",
            "notes.txt": "operator notes",
            "raw_dump.bin": "not part of MVP contract",
        },
    )

    result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    assert (result.package_dir / "signal.bin").exists()
    assert (result.package_dir / "experiment.json").exists()
    assert (result.package_dir / "journal.ndjson").exists()
    assert (result.package_dir / "app.log").exists()
    assert not (result.package_dir / "notes.txt").exists()
    assert not (result.package_dir / "raw_dump.bin").exists()


def test_stage_upload_package_rejects_missing_source_dir(workspace_tmp_path: Path) -> None:
    """Staging начинается только с реально существующей директории пакета."""

    with pytest.raises(UploadStagingError):
        stage_upload_package(
            source_package_dir=workspace_tmp_path / "missing",
            upload_tmp_root=workspace_tmp_path / "upload_tmp",
            upload_session_id=VALID_UPLOAD_SESSION_ID,
            expected_experiment_id="exp_01",
        )
