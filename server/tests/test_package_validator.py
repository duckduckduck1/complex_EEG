"""Tests for EEG experiment package validation."""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest
from app.features.validation import validate_experiment_package


def _write_package(
    package_dir: Path,
    *,
    experiment_id: str = "exp_01",
    signal_samples: int = 1000,
    signal_bytes: bytes | None = None,
    metadata: dict[str, Any] | None = None,
    segments: list[dict[str, Any]] | None = None,
    labels: list[dict[str, Any]] | None = None,
    fbm_events: list[dict[str, Any]] | None = None,
    include_signal: bool = True,
    include_experiment_json: bool = True,
) -> None:
    package_dir.mkdir()

    if include_signal:
        if signal_bytes is None:
            signal_bytes = b"\x00\x00\x00\x00" * signal_samples

        (package_dir / "signal.bin").write_bytes(signal_bytes)

    experiment_json = {
        "experiment_id": experiment_id,
        "metadata": {} if metadata is None else metadata,
        "segments": segments
        if segments is not None
        else [
            {
                "segment_id": "seg_1",
                "start_sample": 0,
                "end_sample": signal_samples,
            }
        ],
        "labels": [] if labels is None else labels,
        "fbm_events": [] if fbm_events is None else fbm_events,
    }
    if include_experiment_json:
        (package_dir / "experiment.json").write_text(
            json.dumps(experiment_json),
            encoding="utf-8",
        )


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Create test data inside the repository instead of the OS temp directory."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


def _error_codes(package_dir: Path, *, expected_experiment_id: str | None = "exp_01") -> set[str]:
    result = validate_experiment_package(
        package_dir,
        expected_experiment_id=expected_experiment_id,
    )
    return {error.code for error in result.errors}


def test_valid_minimal_package_is_accepted(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, metadata={"animal_id": "mouse_1"})

    result = validate_experiment_package(package_dir, expected_experiment_id="exp_01")

    assert result.is_valid is True
    assert result.status == "accepted"
    assert result.experiment_id == "exp_01"
    assert result.metadata == {"animal_id": "mouse_1"}
    assert result.sample_count == 1000
    assert result.signal_size_bytes == 4000
    assert result.errors == []


def test_missing_signal_file_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, include_signal=False)

    assert "validation.missing_file" in _error_codes(package_dir)


def test_missing_experiment_json_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, include_experiment_json=False)

    assert "validation.missing_file" in _error_codes(package_dir)


def test_invalid_experiment_json_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir)
    (package_dir / "experiment.json").write_text("{broken json", encoding="utf-8")

    assert "validation.json_parse_failed" in _error_codes(package_dir)


def test_experiment_id_mismatch_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, experiment_id="exp_02")

    assert "validation.experiment_id_mismatch" in _error_codes(package_dir)


def test_invalid_experiment_id_format_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, experiment_id="../bad")

    assert "validation.experiment_id_invalid" in _error_codes(
        package_dir,
        expected_experiment_id="../bad",
    )


def test_missing_metadata_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir)

    experiment_json = json.loads((package_dir / "experiment.json").read_text(encoding="utf-8"))
    del experiment_json["metadata"]
    (package_dir / "experiment.json").write_text(
        json.dumps(experiment_json),
        encoding="utf-8",
    )

    assert "validation.required_field_missing" in _error_codes(package_dir)


def test_empty_signal_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, signal_bytes=b"")

    assert "validation.signal_empty" in _error_codes(package_dir)


def test_signal_size_not_divisible_by_four_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(package_dir, signal_bytes=b"\x00\x01\x02")

    assert "validation.signal_size_invalid" in _error_codes(package_dir)


def test_segment_out_of_bounds_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        signal_samples=100,
        segments=[{"segment_id": "seg_1", "start_sample": 0, "end_sample": 101}],
    )

    assert "validation.segment_out_of_bounds" in _error_codes(package_dir)


def test_overlapping_segments_are_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        segments=[
            {"segment_id": "seg_1", "start_sample": 0, "end_sample": 100},
            {"segment_id": "seg_2", "start_sample": 50, "end_sample": 150},
        ],
    )

    assert "validation.segment_overlap" in _error_codes(package_dir)


def test_unsorted_segments_are_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        segments=[
            {"segment_id": "seg_1", "start_sample": 100, "end_sample": 200},
            {"segment_id": "seg_2", "start_sample": 50, "end_sample": 60},
        ],
    )

    assert "validation.segment_invalid_range" in _error_codes(package_dir)


def test_invalid_segment_id_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        segments=[{"segment_id": "segment-1", "start_sample": 0, "end_sample": 100}],
    )

    assert "validation.required_field_missing" in _error_codes(package_dir)


def test_label_unknown_segment_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        labels=[{"segment_id": "seg_404", "sample_index": 10, "label_type": "sleep"}],
    )

    assert "validation.label_unknown_segment" in _error_codes(package_dir)


def test_label_out_of_bounds_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        signal_samples=100,
        labels=[{"segment_id": "seg_1", "sample_index": 100, "label_type": "sleep"}],
    )

    assert "validation.label_out_of_bounds" in _error_codes(package_dir)


def test_fbm_event_out_of_bounds_is_rejected(workspace_tmp_path: Path) -> None:
    package_dir = workspace_tmp_path / "exp_01"
    _write_package(
        package_dir,
        signal_samples=100,
        fbm_events=[{"segment_id": "seg_1", "sample_index": 150}],
    )

    assert "validation.fbm_event_out_of_bounds" in _error_codes(package_dir)
