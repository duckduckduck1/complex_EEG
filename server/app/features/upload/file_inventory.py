"""Инвентаризация source-файлов принятого EEG-пакета.

Этот модуль превращает файлы на диске в маленькие записи с размером и sha256.
Позже эти записи можно будет сохранить в таблицу `source_files`.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

from app.features.upload.staging import PACKAGE_FILE_NAMES


class SourceFileInventoryError(ValueError):
    """Ошибка построения inventory для source-директории."""


@dataclass(frozen=True)
class SourceFileInfo:
    """Описание одного source-файла, пригодное для записи в БД."""

    name: str
    relative_path: str
    size_bytes: int
    sha256: str


def build_source_file_inventory(source_dir: str | Path) -> tuple[SourceFileInfo, ...]:
    """Собирает inventory файлов из permanent `source/` директории.

    Функция намеренно берёт только файлы из контракта EEG-пакета. Если рядом
    случайно появятся временные или служебные файлы, они не попадут в будущую
    таблицу `source_files`.
    """

    source_path = Path(source_dir)
    if not source_path.exists() or not source_path.is_dir():
        raise SourceFileInventoryError("source_dir must be an existing directory")

    files: list[SourceFileInfo] = []

    for file_name in sorted(PACKAGE_FILE_NAMES):
        file_path = source_path / file_name
        if not file_path.exists():
            continue

        if not file_path.is_file():
            raise SourceFileInventoryError(f"{file_name} must be a regular file")

        files.append(
            SourceFileInfo(
                name=file_name,
                relative_path=file_name,
                size_bytes=file_path.stat().st_size,
                sha256=_calculate_sha256(file_path),
            )
        )

    return tuple(files)


def _calculate_sha256(file_path: Path) -> str:
    """Считает sha256 потоково, не загружая большой signal.bin целиком в память."""

    digest = hashlib.sha256()

    with file_path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()
