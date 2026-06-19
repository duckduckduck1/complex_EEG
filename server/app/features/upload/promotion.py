"""Перенос валидного staged upload в постоянное файловое хранилище."""

from __future__ import annotations

import shutil
from dataclasses import dataclass
from pathlib import Path

from app.features.upload.staging import PACKAGE_FILE_NAMES, UploadStagingResult
from app.features.validation.package_validator import EXPERIMENT_ID_PATTERN


class UploadPromotionError(ValueError):
    """Ошибка переноса staged upload в permanent experiment storage."""


@dataclass(frozen=True)
class UploadPromotionResult:
    """Результат переноса принятого эксперимента в постоянное хранилище."""

    experiment_id: str
    experiment_dir: Path
    source_dir: Path
    validation_dir: Path
    validation_report_path: Path


def build_experiment_dir(experiments_root: str | Path, experiment_id: str) -> Path:
    """Строит путь постоянной директории эксперимента и проверяет experiment_id.

    Здесь повторяется path-safety проверка, хотя валидатор уже проверял ID.
    Причина практическая: permanent storage — последний рубеж перед записью в
    файловую систему, и он не должен доверять данным из предыдущего слоя вслепую.
    """

    if not EXPERIMENT_ID_PATTERN.fullmatch(experiment_id):
        raise UploadPromotionError("experiment_id has invalid format")

    return Path(experiments_root) / experiment_id


def promote_staged_upload(
    *,
    staging_result: UploadStagingResult,
    experiments_root: str | Path,
) -> UploadPromotionResult:
    """Копирует валидный staged upload в permanent experiment storage.

    Функция не удаляет upload_tmp. Cleanup временных директорий будет отдельной
    задачей, потому что политика retention зависит от статусов БД и runbook.
    """

    if not staging_result.is_valid:
        raise UploadPromotionError("only valid staged uploads can be promoted")

    experiment_id = staging_result.validation_result.experiment_id
    if experiment_id is None:
        raise UploadPromotionError("validated experiment_id is missing")

    if experiment_id != staging_result.expected_experiment_id:
        raise UploadPromotionError("validated experiment_id does not match staging expectation")

    if not staging_result.package_dir.exists() or not staging_result.package_dir.is_dir():
        raise UploadPromotionError("staged source directory is missing")

    if not staging_result.validation_report_path.exists():
        raise UploadPromotionError("validation report is missing")

    experiment_dir = build_experiment_dir(experiments_root, experiment_id)
    if experiment_dir.exists():
        raise UploadPromotionError("experiment directory already exists")

    source_dir = experiment_dir / "source"
    validation_dir = experiment_dir / "validation"
    validation_report_path = validation_dir / "validation_report.json"

    source_dir.mkdir(parents=True, exist_ok=False)
    validation_dir.mkdir(parents=True, exist_ok=False)

    _copy_staged_source_files(
        staged_source_dir=staging_result.package_dir,
        permanent_source_dir=source_dir,
    )
    shutil.copy2(staging_result.validation_report_path, validation_report_path)

    return UploadPromotionResult(
        experiment_id=experiment_id,
        experiment_dir=experiment_dir,
        source_dir=source_dir,
        validation_dir=validation_dir,
        validation_report_path=validation_report_path,
    )


def _copy_staged_source_files(
    *,
    staged_source_dir: Path,
    permanent_source_dir: Path,
) -> None:
    """Копирует из staged source только файлы контракта EEG-пакета."""

    for file_name in PACKAGE_FILE_NAMES:
        source_file = staged_source_dir / file_name
        if not source_file.exists():
            continue

        if not source_file.is_file():
            raise UploadPromotionError(f"{file_name} must be a regular file")

        shutil.copy2(source_file, permanent_source_dir / file_name)
