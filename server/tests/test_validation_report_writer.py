"""Тесты записи JSON-отчёта валидации."""

from __future__ import annotations

import json
from pathlib import Path

from app.features.validation import (
    ValidationErrorItem,
    ValidationResult,
    build_validation_report,
    write_validation_report,
)


def test_build_validation_report_contains_expected_fields() -> None:
    """Отчёт должен содержать стабильные поля для Web UI и диагностики."""

    result = ValidationResult(
        status="validation_failed",
        experiment_id="exp_01",
        metadata={},
        signal_size_bytes=3,
        sample_count=None,
        errors=[
            ValidationErrorItem(
                code="validation.signal_size_invalid",
                message="signal.bin size must be divisible by 4 bytes",
                details={"file": "signal.bin", "size_bytes": 3},
            )
        ],
    )

    report = build_validation_report(result)

    assert report["experiment_id"] == "exp_01"
    assert report["status"] == "validation_failed"
    assert report["signal_size_bytes"] == 3
    assert report["sample_count"] is None
    assert report["warnings"] == []
    assert report["errors"] == [
        {
            "code": "validation.signal_size_invalid",
            "message": "signal.bin size must be divisible by 4 bytes",
            "details": {"file": "signal.bin", "size_bytes": 3},
        }
    ]
    assert "checked_at" in report


def test_write_validation_report_creates_parent_directory_and_file() -> None:
    """Writer должен сам создать директорию validation/ и записать JSON."""

    result = ValidationResult(
        status="accepted",
        experiment_id="exp_01",
        metadata={"animal_id": "mouse_1"},
        signal_size_bytes=4000,
        sample_count=1000,
        errors=[],
    )

    report_path = (
        Path(".test_tmp")
        / "validation_report_writer"
        / "validation"
        / "validation_report.json"
    )

    written_path = write_validation_report(result, report_path)

    assert written_path == report_path
    assert report_path.exists()

    report = json.loads(report_path.read_text(encoding="utf-8"))

    assert report["experiment_id"] == "exp_01"
    assert report["status"] == "accepted"
    assert report["signal_size_bytes"] == 4000
    assert report["sample_count"] == 1000
    assert report["errors"] == []
