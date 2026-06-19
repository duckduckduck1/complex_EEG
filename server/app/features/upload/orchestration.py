"""Оркестрация файлового upload flow без PostgreSQL.

Этот слой склеивает уже готовые шаги:

1. staging во временную директорию upload-сессии;
2. валидация пакета и запись validation_report.json;
3. promotion в permanent storage, если пакет валиден.

HTTP, авторизация и обновление статусов БД будут подключены выше этим слоем.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.features.upload.promotion import (
    UploadPromotionResult,
    promote_staged_upload,
)
from app.features.upload.staging import (
    UploadStagingResult,
    stage_upload_package,
)


@dataclass(frozen=True)
class UploadProcessingResult:
    """Итог одного файлового upload flow."""

    upload_session_id: str
    expected_experiment_id: str
    status: str
    staging_result: UploadStagingResult
    promotion_result: UploadPromotionResult | None

    @property
    def is_accepted(self) -> bool:
        """True, если пакет прошёл валидацию и попал в permanent storage."""

        return self.status == "accepted"

    @property
    def validation_report_path(self) -> Path:
        """Возвращает основной путь к validation_report.json для текущего статуса.

        Для accepted эксперимента главным становится permanent report.
        Для validation_failed главным остаётся report во временной upload-сессии.
        """

        if self.promotion_result is not None:
            return self.promotion_result.validation_report_path

        return self.staging_result.validation_report_path


def process_upload_package(
    *,
    source_package_dir: str | Path,
    upload_tmp_root: str | Path,
    experiments_root: str | Path,
    upload_session_id: str,
    expected_experiment_id: str,
) -> UploadProcessingResult:
    """Выполняет полный файловый upload flow для одной папки эксперимента.

    Если валидация падает, функция не считает это исключением: пользователь
    просто загрузил некорректный пакет, а сервер сохранил report для диагностики.

    Исключения остаются для инфраструктурных ошибок: небезопасный ID,
    отсутствующая source-директория, конфликт permanent storage и похожие случаи.
    """

    staging_result = stage_upload_package(
        source_package_dir=source_package_dir,
        upload_tmp_root=upload_tmp_root,
        upload_session_id=upload_session_id,
        expected_experiment_id=expected_experiment_id,
    )

    if not staging_result.is_valid:
        return UploadProcessingResult(
            upload_session_id=upload_session_id,
            expected_experiment_id=expected_experiment_id,
            status="validation_failed",
            staging_result=staging_result,
            promotion_result=None,
        )

    promotion_result = promote_staged_upload(
        staging_result=staging_result,
        experiments_root=experiments_root,
    )

    return UploadProcessingResult(
        upload_session_id=upload_session_id,
        expected_experiment_id=expected_experiment_id,
        status="accepted",
        staging_result=staging_result,
        promotion_result=promotion_result,
    )
