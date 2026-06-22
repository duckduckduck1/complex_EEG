"""Генератор тестового эксперимента должен создавать пакет, который принимает валидатор."""

from __future__ import annotations

import importlib.util
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest

from app.features.validation.package_validator import validate_experiment_package


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = REPO_ROOT / "scripts" / "dev" / "generate_test_experiment.py"


def _load_generator():
    spec = importlib.util.spec_from_file_location("generate_test_experiment", GENERATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


def test_generated_package_passes_validator(workspace_tmp_path: Path) -> None:
    generator = _load_generator()
    out = workspace_tmp_path / "exp"

    experiment = generator.build_experiment_package(
        out, experiment_id="exp_test_001", sample_count=1000
    )

    result = validate_experiment_package(out, expected_experiment_id="exp_test_001")

    assert result.is_valid, result.errors
    assert result.experiment_id == "exp_test_001"
    assert result.sample_count == 1000
    assert (out / "signal.bin").stat().st_size == 1000 * 4
    assert experiment["segments"][0]["segment_id"] == "seg_1"


def test_generated_package_with_segments_and_optional(workspace_tmp_path: Path) -> None:
    generator = _load_generator()
    out = workspace_tmp_path / "exp"

    generator.build_experiment_package(
        out,
        experiment_id="exp_test_002",
        sample_count=900,
        segment_count=3,
        with_optional=True,
    )

    result = validate_experiment_package(out, expected_experiment_id="exp_test_002")

    assert result.is_valid, result.errors
    assert (out / "journal.ndjson").is_file()
    assert (out / "app.log").is_file()
