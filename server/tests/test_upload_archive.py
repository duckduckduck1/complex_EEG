"""Тесты безопасной распаковки zip-архива EEG-пакета."""

from __future__ import annotations

import io
import zipfile
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest

from app.features.upload import UploadArchiveError, extract_experiment_zip


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


def _build_zip(entries: dict[str, bytes]) -> bytes:
    archive_buffer = io.BytesIO()

    with zipfile.ZipFile(archive_buffer, mode="w") as archive:
        for name, content in entries.items():
            archive.writestr(name, content)

    return archive_buffer.getvalue()


def test_extract_experiment_zip_accepts_root_package(workspace_tmp_path: Path) -> None:
    """Архив может содержать файлы пакета прямо в корне."""

    archive_bytes = _build_zip(
        {
            "signal.bin": b"\x00\x00\x00\x00",
            "experiment.json": b"{}",
        }
    )

    package_dir = extract_experiment_zip(
        archive_bytes=archive_bytes,
        extract_dir=workspace_tmp_path / "extract",
    )

    assert package_dir == workspace_tmp_path / "extract"
    assert (package_dir / "signal.bin").exists()
    assert (package_dir / "experiment.json").exists()


def test_extract_experiment_zip_accepts_single_top_level_folder(workspace_tmp_path: Path) -> None:
    """Архив может содержать одну папку эксперимента внутри."""

    archive_bytes = _build_zip(
        {
            "exp1/signal.bin": b"\x00\x00\x00\x00",
            "exp1/experiment.json": b"{}",
        }
    )

    package_dir = extract_experiment_zip(
        archive_bytes=archive_bytes,
        extract_dir=workspace_tmp_path / "extract",
    )

    assert package_dir == workspace_tmp_path / "extract" / "exp1"


def test_extract_experiment_zip_rejects_bad_zip(workspace_tmp_path: Path) -> None:
    """Невалидный zip не должен попадать в upload flow."""

    extract_dir = workspace_tmp_path / "extract"

    with pytest.raises(UploadArchiveError):
        extract_experiment_zip(
            archive_bytes=b"not a zip",
            extract_dir=extract_dir,
        )

    assert not extract_dir.exists()


def test_extract_experiment_zip_rejects_zip_slip(workspace_tmp_path: Path) -> None:
    """Архив не должен уметь писать файлы за пределы extract_dir."""

    archive_bytes = _build_zip(
        {
            "../evil.txt": b"evil",
            "signal.bin": b"\x00\x00\x00\x00",
            "experiment.json": b"{}",
        }
    )

    with pytest.raises(UploadArchiveError):
        extract_experiment_zip(
            archive_bytes=archive_bytes,
            extract_dir=workspace_tmp_path / "extract",
        )


def test_extract_experiment_zip_rejects_archive_without_package(workspace_tmp_path: Path) -> None:
    """Архив без обязательных файлов EEG-пакета отклоняется."""

    archive_bytes = _build_zip({"notes.txt": b"hello"})

    with pytest.raises(UploadArchiveError):
        extract_experiment_zip(
            archive_bytes=archive_bytes,
            extract_dir=workspace_tmp_path / "extract",
        )
