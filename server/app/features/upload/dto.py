"""DTO для безопасного ответа upload flow наружу.

Внутренние upload-объекты содержат filesystem paths. Для API и Web UI это
опасная деталь реализации, поэтому наружу отдаём только стабильные поля:
статус, ошибки, размеры файлов, checksum и относительные имена source-файлов.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

from app.features.upload.orchestration import UploadProcessingResult


ValidationReportScope = Literal["upload_tmp", "permanent"]


class UploadValidationErrorDto(BaseModel):
    """Ошибка валидации в формате, безопасном для API."""

    code: str
    message: str
    details: dict[str, Any] = Field(default_factory=dict)


class UploadSourceFileDto(BaseModel):
    """Source-файл, который можно показать Web UI или сохранить в БД."""

    name: str
    relative_path: str
    size_bytes: int
    sha256: str


class UploadProcessingResponseDto(BaseModel):
    """Публичный ответ полного файлового upload flow."""

    upload_session_id: str
    experiment_id: str | None
    status: str
    accepted: bool
    validation_report_scope: ValidationReportScope
    signal_size_bytes: int | None
    sample_count: int | None
    source_files: list[UploadSourceFileDto] = Field(default_factory=list)
    errors: list[UploadValidationErrorDto] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


def build_upload_processing_response(
    result: UploadProcessingResult,
) -> UploadProcessingResponseDto:
    """Строит API-safe DTO из внутреннего результата upload flow.

    Здесь намеренно не возвращаются абсолютные пути к `upload_tmp` или
    `experiments`. Клиенту достаточно знать статус и диагностические данные,
    а реальные пути остаются внутренней ответственностью сервера.
    """

    validation_result = result.staging_result.validation_result
    source_files = []

    if result.promotion_result is not None:
        source_files = [
            UploadSourceFileDto(
                name=file.name,
                relative_path=file.relative_path,
                size_bytes=file.size_bytes,
                sha256=file.sha256,
            )
            for file in result.promotion_result.source_files
        ]

    return UploadProcessingResponseDto(
        upload_session_id=result.upload_session_id,
        experiment_id=validation_result.experiment_id,
        status=result.status,
        accepted=result.is_accepted,
        validation_report_scope="permanent" if result.is_accepted else "upload_tmp",
        signal_size_bytes=validation_result.signal_size_bytes,
        sample_count=validation_result.sample_count,
        source_files=source_files,
        errors=[
            UploadValidationErrorDto(
                code=error.code,
                message=error.message,
                details=error.details,
            )
            for error in validation_result.errors
        ],
        warnings=validation_result.warnings,
    )
