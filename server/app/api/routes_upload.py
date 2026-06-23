"""Upload endpoint'ы серверного API.

В этом модуле живут только dev/test endpoint'ы. Они нужны для локальной
диагностики файлового upload flow и не используются production Web UI.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, Request, status
from pydantic import BaseModel, Field

from app.core.config import settings
from app.features.upload import (
    UploadArchiveError,
    UploadProcessingResponseDto,
    UploadPromotionError,
    UploadStagingError,
    build_upload_processing_response,
    build_upload_session_dir,
    extract_experiment_zip,
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
    filesystem path с клиента и использует authenticated upload sessions.
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


@router.post(
    "/process-zip",
    response_model=UploadProcessingResponseDto,
)
async def process_zip_upload(
    request: Request,
    upload_session_id: str = Query(min_length=1),
    experiment_id: str = Query(min_length=1),
) -> UploadProcessingResponseDto:
    """Запускает файловый upload flow для zip-архива EEG-пакета.

    Endpoint всё ещё dev/test, потому что настоящая production-загрузка должна
    быть связана с web-auth, upload session в БД и лимитами размера запроса.
    """

    _ensure_local_upload_endpoint_enabled()

    archive_bytes = await request.body()

    extract_dir = Path(settings.upload_tmp_dir) / "_zip_extract" / upload_session_id

    try:
        # Zip распаковывается до staging, поэтому upload_session_id проверяем здесь
        # заранее. Иначе query-параметр мог бы стать частью filesystem path.
        build_upload_session_dir(settings.upload_tmp_dir, upload_session_id)
        source_package_dir = extract_experiment_zip(
            archive_bytes=archive_bytes,
            extract_dir=extract_dir,
        )
        result = process_upload_package(
            source_package_dir=source_package_dir,
            upload_tmp_root=settings.upload_tmp_dir,
            experiments_root=settings.experiments_dir,
            upload_session_id=upload_session_id,
            expected_experiment_id=experiment_id,
        )
    except UploadArchiveError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "upload.archive_invalid",
                "message": str(exc),
            },
        ) from exc
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
                "message": "Dev upload endpoint is disabled",
            },
        )
