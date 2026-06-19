"""Validation for uploaded EEG experiment packages.

The validator checks the filesystem package before the server moves it into
permanent storage or starts pipeline processing. It does not mutate files and it
does not talk to the database.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


EXPERIMENT_ID_PATTERN = re.compile(r"^[a-zA-Z0-9_-]{1,64}$")
SEGMENT_ID_PATTERN = re.compile(r"^seg_[1-9][0-9]*$")
SIGNAL_SAMPLE_SIZE_BYTES = 4


@dataclass(frozen=True)
class ValidationErrorItem:
    """One machine-readable validation error."""

    code: str
    message: str
    details: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class ValidationResult:
    """Result returned by the package validator."""

    status: str
    experiment_id: str | None
    metadata: dict[str, Any]
    signal_size_bytes: int | None
    sample_count: int | None
    errors: list[ValidationErrorItem]
    warnings: list[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        """True when the package can be accepted by the server."""

        return self.status == "accepted"


def validate_experiment_package(
    package_path: str | Path,
    *,
    expected_experiment_id: str | None = None,
) -> ValidationResult:
    """Validate an EEG experiment package directory.

    `expected_experiment_id` is the value from the upload session. Passing it
    protects the server from accepting a package whose JSON belongs to another
    experiment.
    """

    package_dir = Path(package_path)
    errors: list[ValidationErrorItem] = []

    signal_path = package_dir / "signal.bin"
    metadata_path = package_dir / "experiment.json"

    signal_size_bytes, sample_count = _validate_signal_file(signal_path, errors)
    experiment_json = _read_experiment_json(metadata_path, errors)

    experiment_id: str | None = None
    metadata: dict[str, Any] = {}

    if isinstance(experiment_json, dict):
        experiment_id = _validate_experiment_id(
            experiment_json,
            expected_experiment_id=expected_experiment_id,
            errors=errors,
        )
        metadata = _validate_metadata(experiment_json, errors)
        segment_ranges = _validate_segments(experiment_json, sample_count, errors)
        _validate_labels(experiment_json, segment_ranges, errors)
        _validate_fbm_events(experiment_json, segment_ranges, errors)

    status = "accepted" if not errors else "validation_failed"

    return ValidationResult(
        status=status,
        experiment_id=experiment_id,
        metadata=metadata,
        signal_size_bytes=signal_size_bytes,
        sample_count=sample_count,
        errors=errors,
    )


def _validate_signal_file(
    signal_path: Path,
    errors: list[ValidationErrorItem],
) -> tuple[int | None, int | None]:
    if not signal_path.exists() or not signal_path.is_file():
        errors.append(
            ValidationErrorItem(
                code="validation.missing_file",
                message="Required file signal.bin is missing",
                details={"file": "signal.bin"},
            )
        )
        return None, None

    signal_size_bytes = signal_path.stat().st_size

    if signal_size_bytes == 0:
        errors.append(
            ValidationErrorItem(
                code="validation.signal_empty",
                message="signal.bin is empty",
                details={"file": "signal.bin"},
            )
        )
        return signal_size_bytes, 0

    # Each sample is one int32 amplitude value, so a valid file is divisible by 4.
    if signal_size_bytes % SIGNAL_SAMPLE_SIZE_BYTES != 0:
        errors.append(
            ValidationErrorItem(
                code="validation.signal_size_invalid",
                message="signal.bin size must be divisible by 4 bytes",
                details={
                    "file": "signal.bin",
                    "size_bytes": signal_size_bytes,
                },
            )
        )
        return signal_size_bytes, None

    return signal_size_bytes, signal_size_bytes // SIGNAL_SAMPLE_SIZE_BYTES


def _read_experiment_json(
    metadata_path: Path,
    errors: list[ValidationErrorItem],
) -> dict[str, Any] | None:
    if not metadata_path.exists() or not metadata_path.is_file():
        errors.append(
            ValidationErrorItem(
                code="validation.missing_file",
                message="Required file experiment.json is missing",
                details={"file": "experiment.json"},
            )
        )
        return None

    try:
        raw_value = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        errors.append(
            ValidationErrorItem(
                code="validation.json_parse_failed",
                message="experiment.json must be valid UTF-8 JSON",
                details={"file": "experiment.json", "reason": str(exc)},
            )
        )
        return None

    if not isinstance(raw_value, dict):
        errors.append(
            ValidationErrorItem(
                code="validation.required_field_missing",
                message="experiment.json root must be an object",
                details={"file": "experiment.json"},
            )
        )
        return None

    return raw_value


def _validate_experiment_id(
    experiment_json: dict[str, Any],
    *,
    expected_experiment_id: str | None,
    errors: list[ValidationErrorItem],
) -> str | None:
    experiment_id = experiment_json.get("experiment_id")

    if not isinstance(experiment_id, str):
        errors.append(
            ValidationErrorItem(
                code="validation.required_field_missing",
                message="experiment_id is required",
                details={"field": "experiment_id"},
            )
        )
        return None

    if not EXPERIMENT_ID_PATTERN.fullmatch(experiment_id):
        errors.append(
            ValidationErrorItem(
                code="validation.experiment_id_invalid",
                message="experiment_id has invalid format",
                details={"experiment_id": experiment_id},
            )
        )

    if expected_experiment_id is not None and experiment_id != expected_experiment_id:
        errors.append(
            ValidationErrorItem(
                code="validation.experiment_id_mismatch",
                message="experiment_id does not match upload session",
                details={
                    "expected_experiment_id": expected_experiment_id,
                    "actual_experiment_id": experiment_id,
                },
            )
        )

    return experiment_id


def _validate_metadata(
    experiment_json: dict[str, Any],
    errors: list[ValidationErrorItem],
) -> dict[str, Any]:
    metadata = experiment_json.get("metadata")

    if metadata is None:
        errors.append(
            ValidationErrorItem(
                code="validation.required_field_missing",
                message="metadata is required",
                details={"field": "metadata"},
            )
        )
        return {}

    if not isinstance(metadata, dict):
        errors.append(
            ValidationErrorItem(
                code="validation.required_field_missing",
                message="metadata must be an object",
                details={"field": "metadata"},
            )
        )
        return {}

    return metadata


def _validate_segments(
    experiment_json: dict[str, Any],
    sample_count: int | None,
    errors: list[ValidationErrorItem],
) -> dict[str, tuple[int, int]]:
    segments = experiment_json.get("segments")

    if not isinstance(segments, list) or not segments:
        errors.append(
            ValidationErrorItem(
                code="validation.required_field_missing",
                message="segments must be a non-empty array",
                details={"field": "segments"},
            )
        )
        return {}

    previous_start_sample: int | None = None
    previous_end_sample: int | None = None
    segment_ranges: dict[str, tuple[int, int]] = {}

    for index, segment in enumerate(segments):
        if not isinstance(segment, dict):
            errors.append(
                ValidationErrorItem(
                    code="validation.segment_invalid_range",
                    message="segment must be an object",
                    details={"segment_index": index},
                )
            )
            continue

        segment_id = segment.get("segment_id")
        start_sample = segment.get("start_sample")
        end_sample = segment.get("end_sample")
        segment_id_is_valid = isinstance(segment_id, str) and bool(SEGMENT_ID_PATTERN.fullmatch(segment_id))

        if not segment_id_is_valid:
            errors.append(
                ValidationErrorItem(
                    code="validation.required_field_missing",
                    message="segment_id must match seg_<N>",
                    details={"segment_index": index, "segment_id": segment_id},
                )
            )

        if not _is_int(start_sample) or not _is_int(end_sample):
            errors.append(
                ValidationErrorItem(
                    code="validation.segment_invalid_range",
                    message="segment start_sample and end_sample must be integers",
                    details={"segment_index": index},
                )
            )
            continue

        # Segments are half-open intervals: start is included, end is excluded.
        if start_sample < 0 or end_sample <= start_sample:
            errors.append(
                ValidationErrorItem(
                    code="validation.segment_invalid_range",
                    message="segment range is invalid",
                    details={
                        "segment_id": segment_id,
                        "start_sample": start_sample,
                        "end_sample": end_sample,
                    },
                )
            )
            continue

        if sample_count is not None and end_sample > sample_count:
            errors.append(
                ValidationErrorItem(
                    code="validation.segment_out_of_bounds",
                    message="segment end_sample exceeds signal sample count",
                    details={
                        "segment_id": segment_id,
                        "end_sample": end_sample,
                        "sample_count": sample_count,
                    },
                )
            )

        if previous_start_sample is not None and start_sample < previous_start_sample:
            errors.append(
                ValidationErrorItem(
                    code="validation.segment_invalid_range",
                    message="segments must be sorted by start_sample ascending",
                    details={
                        "segment_id": segment_id,
                        "start_sample": start_sample,
                        "previous_start_sample": previous_start_sample,
                    },
                )
            )
        elif previous_end_sample is not None and start_sample < previous_end_sample:
            errors.append(
                ValidationErrorItem(
                    code="validation.segment_overlap",
                    message="segments must not overlap",
                    details={
                        "segment_id": segment_id,
                        "start_sample": start_sample,
                        "previous_end_sample": previous_end_sample,
                    },
                )
            )

        previous_start_sample = start_sample
        previous_end_sample = end_sample

        if segment_id_is_valid:
            segment_ranges[segment_id] = (start_sample, end_sample)

    return segment_ranges


def _validate_labels(
    experiment_json: dict[str, Any],
    segment_ranges: dict[str, tuple[int, int]],
    errors: list[ValidationErrorItem],
) -> None:
    labels = experiment_json.get("labels", [])

    if labels is None:
        return

    if not isinstance(labels, list):
        errors.append(
            ValidationErrorItem(
                code="validation.label_unknown_segment",
                message="labels must be an array when present",
                details={"field": "labels"},
            )
        )
        return

    for index, label in enumerate(labels):
        if not isinstance(label, dict):
            errors.append(
                ValidationErrorItem(
                    code="validation.label_unknown_segment",
                    message="label must be an object",
                    details={"label_index": index},
                )
            )
            continue

        segment_id = label.get("segment_id")
        segment_range = _get_existing_segment_range(
            segment_id=segment_id,
            segment_ranges=segment_ranges,
            errors=errors,
            code="validation.label_unknown_segment",
            message="label references unknown segment",
            details_key="label_index",
            details_index=index,
        )
        if segment_range is None:
            continue

        if "sample_index" in label:
            sample_index = label["sample_index"]
            if not _is_int(sample_index) or not _sample_inside_segment(sample_index, segment_range):
                errors.append(
                    ValidationErrorItem(
                        code="validation.label_out_of_bounds",
                        message="label sample_index is outside its segment",
                        details={
                            "label_index": index,
                            "segment_id": segment_id,
                            "sample_index": sample_index,
                        },
                    )
                )

        if "start_sample" in label or "end_sample" in label:
            start_sample = label.get("start_sample")
            end_sample = label.get("end_sample")
            if (
                not _is_int(start_sample)
                or not _is_int(end_sample)
                or start_sample >= end_sample
                or not _sample_inside_segment(start_sample, segment_range)
                or not _sample_inside_segment(end_sample - 1, segment_range)
            ):
                errors.append(
                    ValidationErrorItem(
                        code="validation.label_out_of_bounds",
                        message="label interval is outside its segment",
                        details={
                            "label_index": index,
                            "segment_id": segment_id,
                            "start_sample": start_sample,
                            "end_sample": end_sample,
                        },
                    )
                )


def _validate_fbm_events(
    experiment_json: dict[str, Any],
    segment_ranges: dict[str, tuple[int, int]],
    errors: list[ValidationErrorItem],
) -> None:
    fbm_events = experiment_json.get("fbm_events", [])

    if fbm_events is None:
        return

    if not isinstance(fbm_events, list):
        errors.append(
            ValidationErrorItem(
                code="validation.fbm_event_out_of_bounds",
                message="fbm_events must be an array when present",
                details={"field": "fbm_events"},
            )
        )
        return

    for index, event in enumerate(fbm_events):
        if not isinstance(event, dict):
            errors.append(
                ValidationErrorItem(
                    code="validation.fbm_event_out_of_bounds",
                    message="fbm_event must be an object",
                    details={"fbm_event_index": index},
                )
            )
            continue

        segment_id = event.get("segment_id")
        segment_range = _get_existing_segment_range(
            segment_id=segment_id,
            segment_ranges=segment_ranges,
            errors=errors,
            code="validation.fbm_event_out_of_bounds",
            message="fbm_event references unknown segment",
            details_key="fbm_event_index",
            details_index=index,
        )
        if segment_range is None:
            continue

        if "sample_index" in event:
            sample_index = event["sample_index"]
            if not _is_int(sample_index) or not _sample_inside_segment(sample_index, segment_range):
                errors.append(
                    ValidationErrorItem(
                        code="validation.fbm_event_out_of_bounds",
                        message="fbm_event sample_index is outside its segment",
                        details={
                            "fbm_event_index": index,
                            "segment_id": segment_id,
                            "sample_index": sample_index,
                        },
                    )
                )


def _get_existing_segment_range(
    *,
    segment_id: Any,
    segment_ranges: dict[str, tuple[int, int]],
    errors: list[ValidationErrorItem],
    code: str,
    message: str,
    details_key: str,
    details_index: int,
) -> tuple[int, int] | None:
    if not isinstance(segment_id, str) or segment_id not in segment_ranges:
        errors.append(
            ValidationErrorItem(
                code=code,
                message=message,
                details={details_key: details_index, "segment_id": segment_id},
            )
        )
        return None

    return segment_ranges[segment_id]


def _sample_inside_segment(sample_index: int, segment_range: tuple[int, int]) -> bool:
    start_sample, end_sample = segment_range
    return start_sample <= sample_index < end_sample


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)
