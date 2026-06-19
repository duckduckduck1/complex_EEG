"""Безопасная распаковка zip-архива EEG-пакета."""

from __future__ import annotations

import io
import zipfile
from pathlib import Path


REQUIRED_PACKAGE_FILES = frozenset({"signal.bin", "experiment.json"})


class UploadArchiveError(ValueError):
    """Ошибка чтения или распаковки upload-архива."""


def extract_experiment_zip(
    *,
    archive_bytes: bytes,
    extract_dir: str | Path,
) -> Path:
    """Распаковывает zip-архив и возвращает директорию EEG-пакета.

    Поддерживаются два распространённых варианта:

    1. `signal.bin` и `experiment.json` лежат прямо в корне архива;
    2. в архиве есть одна верхнеуровневая папка, внутри которой лежит пакет.

    Любые попытки записать файл за пределы `extract_dir` запрещены.
    """

    if not archive_bytes:
        raise UploadArchiveError("zip archive is empty")

    destination = Path(extract_dir)
    if destination.exists():
        raise UploadArchiveError("zip extract directory already exists")

    try:
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            destination.mkdir(parents=True, exist_ok=False)
            _safe_extract_zip(archive=archive, destination=destination)
    except zipfile.BadZipFile as exc:
        raise UploadArchiveError("request body must be a valid zip archive") from exc

    return _find_experiment_package_dir(destination)


def _safe_extract_zip(*, archive: zipfile.ZipFile, destination: Path) -> None:
    """Извлекает zip entries только если они остаются внутри destination."""

    destination_root = destination.resolve()

    for member in archive.infolist():
        member_name = member.filename

        if not member_name or member_name.endswith("/"):
            continue

        # Windows-style separators в zip entry запрещаем явно, чтобы path-check
        # был одинаковым на Windows и Linux.
        if "\\" in member_name:
            raise UploadArchiveError("zip entry contains forbidden path separator")

        target_path = destination / member_name
        resolved_target = target_path.resolve()

        if not resolved_target.is_relative_to(destination_root):
            raise UploadArchiveError("zip entry escapes extract directory")

        target_path.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(member) as source, target_path.open("wb") as target:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                target.write(chunk)


def _find_experiment_package_dir(extract_dir: Path) -> Path:
    """Находит директорию, где лежат обязательные файлы EEG-пакета."""

    if _contains_required_package_files(extract_dir):
        return extract_dir

    candidates = [
        path
        for path in extract_dir.iterdir()
        if path.is_dir() and _contains_required_package_files(path)
    ]

    if len(candidates) == 1:
        return candidates[0]

    if not candidates:
        raise UploadArchiveError("zip archive does not contain an EEG package")

    raise UploadArchiveError("zip archive contains multiple EEG package candidates")


def _contains_required_package_files(path: Path) -> bool:
    return all((path / file_name).is_file() for file_name in REQUIRED_PACKAGE_FILES)
