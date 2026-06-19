"""Подготовка временной директории upload-сессии.

Этот модуль не знает про HTTP и PostgreSQL. Его задача ниже уровнем:
принять локальную папку EEG-пакета, положить её во временное хранилище,
запустить валидатор и сохранить validation_report.json.
"""

from __future__ import annotations

import re
import shutil
from dataclasses import dataclass
from pathlib import Path

from app.features.validation import (
    ValidationResult,
    validate_experiment_package,
    write_validation_report,
)


UPLOAD_SESSION_ID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")
PACKAGE_FILE_NAMES = frozenset(
    {
        "signal.bin",
        "experiment.json",
        "journal.ndjson",
        "app.log",
    }
)


class UploadStagingError(ValueError):
    """Ошибка подготовки временной директории upload-сессии."""


@dataclass(frozen=True)
class UploadStagingResult:
    """Результат файловой подготовки upload-сессии."""

    upload_session_id: str
    expected_experiment_id: str
    session_dir: Path
    package_dir: Path
    validation_report_path: Path
    validation_result: ValidationResult

    @property
    def is_valid(self) -> bool:
        """True, если пакет прошёл валидацию и может двигаться дальше."""

        return self.validation_result.is_valid


def build_upload_session_dir(upload_tmp_root: str | Path, upload_session_id: str) -> Path:
    """Строит путь временной upload-сессии и защищает его от path traversal.

    `upload_session_id` приходит из server-side upload session. Даже если позже
    его случайно передадут из внешнего запроса напрямую, этот слой не позволит
    превратить ID в путь вроде `../../etc/passwd`.
    """

    if not UPLOAD_SESSION_ID_PATTERN.fullmatch(upload_session_id):
        raise UploadStagingError(
            "upload_session_id must be a 26-character uppercase ULID"
        )

    return Path(upload_tmp_root) / upload_session_id


def stage_upload_package(
    *,
    source_package_dir: str | Path,
    upload_tmp_root: str | Path,
    upload_session_id: str,
    expected_experiment_id: str,
) -> UploadStagingResult:
    """Копирует EEG-пакет во временную upload-директорию и валидирует его.

    Функция специально не переносит пакет в permanent storage. Это произойдёт
    позже, когда появится upload orchestration с БД, статусами и транзакциями.
    """

    source_dir = Path(source_package_dir)
    if not source_dir.exists() or not source_dir.is_dir():
        raise UploadStagingError("source_package_dir must be an existing directory")

    session_dir = build_upload_session_dir(upload_tmp_root, upload_session_id)
    if session_dir.exists():
        raise UploadStagingError("upload session directory already exists")

    package_dir = session_dir / "source"
    report_path = session_dir / "validation_report.json"

    session_dir.mkdir(parents=True, exist_ok=False)
    _copy_package_contract_files(source_dir=source_dir, package_dir=package_dir)

    validation_result = validate_experiment_package(
        package_dir,
        expected_experiment_id=expected_experiment_id,
    )
    write_validation_report(validation_result, report_path)

    return UploadStagingResult(
        upload_session_id=upload_session_id,
        expected_experiment_id=expected_experiment_id,
        session_dir=session_dir,
        package_dir=package_dir,
        validation_report_path=report_path,
        validation_result=validation_result,
    )


def _copy_package_contract_files(*, source_dir: Path, package_dir: Path) -> None:
    """Копирует только файлы, входящие в контракт EEG-пакета.

    Пользователь может выбрать папку, где случайно лежат лишние файлы. На первом
    стенде мы не тащим их в upload_tmp, чтобы временное хранилище было
    предсказуемым и соответствовало документации.
    """

    # session_dir создаётся новой для каждой upload-сессии, поэтому source/
    # ещё не может читаться другим процессом. Можно писать сразу в финальную
    # директорию без rename(), что также упрощает запуск тестов на Windows.
    package_dir.mkdir(parents=True, exist_ok=False)

    for file_name in PACKAGE_FILE_NAMES:
        source_file = source_dir / file_name
        if not source_file.exists():
            continue

        if not source_file.is_file():
            raise UploadStagingError(f"{file_name} must be a regular file")

        shutil.copy2(source_file, package_dir / file_name)
