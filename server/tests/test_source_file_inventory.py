"""Тесты inventory для source-файлов EEG-пакета."""

from __future__ import annotations

import hashlib
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest

from app.features.upload import (
    SourceFileInventoryError,
    build_source_file_inventory,
)


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


def test_build_source_file_inventory_returns_size_and_sha256(workspace_tmp_path: Path) -> None:
    """Inventory должен возвращать размер и checksum каждого контрактного файла."""

    source_dir = workspace_tmp_path / "source"
    source_dir.mkdir()
    signal_bytes = b"\x01\x00\x00\x00" * 3
    experiment_json = b'{"experiment_id":"exp_01"}'
    source_files = {
        "signal.bin": signal_bytes,
        "experiment.json": experiment_json,
        "journal.ndjson": b'{"type":"experiment_started"}\n',
        "app.log": b"diagnostics",
    }

    for file_name, content in source_files.items():
        (source_dir / file_name).write_bytes(content)

    inventory = build_source_file_inventory(source_dir)

    by_name = {item.name: item for item in inventory}
    assert set(by_name) == set(source_files)

    for file_name, content in source_files.items():
        assert by_name[file_name].relative_path == file_name
        assert by_name[file_name].size_bytes == len(content)
        assert by_name[file_name].sha256 == hashlib.sha256(content).hexdigest()


def test_build_source_file_inventory_ignores_unknown_files(workspace_tmp_path: Path) -> None:
    """Лишние файлы не должны попадать в inventory будущей таблицы source_files."""

    source_dir = workspace_tmp_path / "source"
    source_dir.mkdir()
    (source_dir / "signal.bin").write_bytes(b"\x00\x00\x00\x00")
    (source_dir / "experiment.json").write_text("{}", encoding="utf-8")
    (source_dir / "operator_notes.txt").write_text("manual notes", encoding="utf-8")

    inventory = build_source_file_inventory(source_dir)

    assert {item.name for item in inventory} == {"experiment.json", "signal.bin"}


def test_build_source_file_inventory_rejects_missing_source_dir(workspace_tmp_path: Path) -> None:
    """Inventory строится только для реально существующей source-директории."""

    with pytest.raises(SourceFileInventoryError):
        build_source_file_inventory(workspace_tmp_path / "missing")
