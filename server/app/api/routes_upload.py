"""Upload endpoint'ы серверного API.

В этой ветке добавлен только dev/test endpoint, который принимает путь к уже
существующей локальной папке на серверной машине. Он нужен, чтобы проверить
backend flow end-to-end до реализации настоящей browser upload формы.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.core.config import settings
from app.features.upload import (
    UploadProcessingResponseDto,
    UploadPromotionError,
    UploadStagingError,
    build_upload_processing_response,
    process_upload_package,
)


router = APIRouter(prefix="/api/v1/dev/uploads", tags=["dev-upload"])


class ProcessLocalFolderRequest(BaseModel):
    """Запрос dev/test endpoint'а для обработки локальной папки эксперимента."""

    source_package_dir: str = Field(min_length=1)
    upload_session_id: str = Field(min_length=1)
    experiment_id: str = Field(min_length=1)


@router.post(
    "/process-local-folder",
    response_model=UploadProcessingResponseDto,
)
def process_local_folder_upload(
    request: ProcessLocalFolderRequest,
) -> UploadProcessingResponseDto:
    """Запускает файловый upload flow для локальной папки на сервере.

    Это не production upload endpoint. Production Web UI не должен передавать
    filesystem path с клиента. Позже появится upload через multipart/archive.
    """

    _ensure_local_upload_endpoint_enabled()

    try:
        result = process_upload_package(
            source_package_dir=request.source_package_dir,
            upload_tmp_root=settings.upload_tmp_dir,
            experiments_root=settings.experiments_dir,
            upload_session_id=request.upload_session_id,
            expected_experiment_id=request.experiment_id,
        )
    except UploadStagingError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "upload.staging_failed",
                "message": str(exc),
            },
        ) from exc
    except UploadPromotionError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "upload.promotion_failed",
                "message": str(exc),
            },
        ) from exc

    return build_upload_processing_response(result)


def _ensure_local_upload_endpoint_enabled() -> None:
    """Запрещает dev/test endpoint вне явно разрешённой среды."""

    allowed_envs = {"local", "dev", "test"}
    if settings.app_env not in allowed_envs or not settings.enable_local_upload_endpoint:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "upload.local_endpoint_disabled",
                "message": "Local folder upload endpoint is disabled",
            },
        )
