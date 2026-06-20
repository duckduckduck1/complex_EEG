"""Тесты переноса staged upload в permanent experiment storage."""

from __future__ import annotations

import json
from collections.abc import Iterator
from dataclasses import replace
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest

from app.features.upload import (
    UploadPromotionError,
    build_experiment_dir,
    promote_staged_upload,
    stage_upload_package,
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


def test_build_experiment_dir_rejects_path_traversal() -> None:
    """experiment_id не должен превращаться в небезопасный filesystem path."""

    with pytest.raises(UploadPromotionError):
        build_experiment_dir("/srv/complex_eeg/experiments", "../bad")


def test_promote_staged_upload_creates_permanent_layout(workspace_tmp_path: Path) -> None:
    """Валидный staged upload переносится в permanent layout эксперимента."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(
        source_package_dir,
        extra_files={
            "journal.ndjson": '{"type":"experiment_started"}',
            "app.log": "application diagnostics",
        },
    )
    staging_result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    result = promote_staged_upload(
        staging_result=staging_result,
        experiments_root=experiments_root,
    )

    assert result.experiment_id == "exp_01"
    assert result.experiment_dir == experiments_root / "exp_01"
    assert result.source_dir == result.experiment_dir / "source"
    assert result.validation_dir == result.experiment_dir / "validation"
    assert result.validation_report_path == result.validation_dir / "validation_report.json"
    assert (result.source_dir / "signal.bin").exists()
    assert (result.source_dir / "experiment.json").exists()
    assert (result.source_dir / "journal.ndjson").exists()
    assert (result.source_dir / "app.log").exists()
    assert {item.name for item in result.source_files} == {
        "app.log",
        "experiment.json",
        "journal.ndjson",
        "signal.bin",
    }

    report = json.loads(result.validation_report_path.read_text(encoding="utf-8"))
    assert report["status"] == "accepted"
    assert report["experiment_id"] == "exp_01"


def test_promote_staged_upload_rejects_invalid_validation_result(workspace_tmp_path: Path) -> None:
    """Невалидный staged upload не должен попадать в permanent storage."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir, include_signal=False)
    staging_result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )

    with pytest.raises(UploadPromotionError):
        promote_staged_upload(
            staging_result=staging_result,
            experiments_root=experiments_root,
        )


def test_promote_staged_upload_rejects_existing_experiment_dir(workspace_tmp_path: Path) -> None:
    """Permanent storage не должен перезаписывать уже принятый эксперимент."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir)
    staging_result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )
    (experiments_root / "exp_01").mkdir(parents=True)

    with pytest.raises(UploadPromotionError):
        promote_staged_upload(
            staging_result=staging_result,
            experiments_root=experiments_root,
        )


def test_promote_staged_upload_requires_validation_report(workspace_tmp_path: Path) -> None:
    """Permanent storage должен получать validation_report.json вместе с source."""

    source_package_dir = workspace_tmp_path / "incoming_exp"
    upload_tmp_root = workspace_tmp_path / "upload_tmp"
    experiments_root = workspace_tmp_path / "experiments"
    _write_package(source_package_dir)
    staging_result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=VALID_UPLOAD_SESSION_ID,
        expected_experiment_id="exp_01",
    )
    staging_result = replace(
        staging_result,
        validation_report_path=staging_result.session_dir / "missing_report.json",
    )

    with pytest.raises(UploadPromotionError):
        promote_staged_upload(
            staging_result=staging_result,
            experiments_root=experiments_root,
        )
