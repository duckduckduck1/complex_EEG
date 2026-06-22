"""HTTP API для upload sessions.

Этот слой принимает ручную загрузку EEG experiment package через Web UI:
создаёт session, принимает файлы, показывает статус, отменяет загрузку и
запускает complete flow. Все production endpoints требуют web-auth.
"""

from __future__ import annotations

import shutil
from pathlib import Path as FsPath
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Request, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps_auth import require_current_user
from app.core.config import settings
from app.db.session import get_db_session
from app.features.upload.dto import UploadSourceFileDto, UploadValidationErrorDto
from app.features.auth import CurrentUser
from app.features.upload.session_service import (
    ActiveUploadSessionAlreadyExistsError,
    DEFAULT_UPLOAD_FILES,
    ExperimentAlreadyRegisteredError,
    UploadCompletionResult,
    UploadFileTarget,
    UploadLocalCleanupError,
    UploadObjectStorageUnavailableError,
    UploadSessionAlreadyExistsError,
    UploadSessionIncompleteError,
    UploadSessionNotFoundError,
    UploadSessionService,
    UploadSessionServiceError,
    UploadSessionStateConflictError,
    UploadSessionView,
    SqlAlchemyUploadSessionRepository,
)
from app.features.upload.bronze_storage import MinioBronzeObjectStorage


router = APIRouter(prefix="/api/v1/uploads", tags=["uploads"])


class CreateUploadSessionRequest(BaseModel):
    """Payload создания upload session."""

    experiment_id: str = Field(
        min_length=1,
        max_length=64,
    )
    display_name: str | None = Field(default=None, max_length=256)
    expected_files: list[str] = Field(default_factory=lambda: list(DEFAULT_UPLOAD_FILES))


class CreateUploadSessionResponse(BaseModel):
    """Ответ после создания upload session."""

    upload_session_id: str
    experiment_id: str
    status: str
    upload_base_url: str
    expires_at: str


class UploadSessionStatusResponse(BaseModel):
    """Публичный статус upload session."""

    upload_session_id: str
    experiment_id: str
    status: str
    expected_files: list[str]
    uploaded_files: list[str]
    expires_at: str


class CompleteUploadSessionResponse(BaseModel):
    """Ответ complete upload без внутренних filesystem paths."""

    upload_session_id: str
    experiment_id: str
    status: str
    accepted: bool
    validation_report_scope: str | None = None
    signal_size_bytes: int | None = None
    sample_count: int | None = None
    source_files: list[UploadSourceFileDto] = Field(default_factory=list)
    errors: list[UploadValidationErrorDto] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class UploadFileTooLargeError(ValueError):
    """Request body превысил лимит upload-файла."""


def get_upload_session_service(
    db: Annotated[Session, Depends(get_db_session)],
) -> UploadSessionService:
    """Собирает service-слой для HTTP request.

    Service не зависит от FastAPI и auth напрямую: HTTP layer отдельно проверяет
    пользователя, а сюда передаёт только repository и filesystem-настройки.
    """

    return UploadSessionService(
        repository=SqlAlchemyUploadSessionRepository(db),
        upload_tmp_root=settings.upload_tmp_dir,
        experiments_root=settings.experiments_dir,
        ttl_hours=settings.upload_session_ttl_hours,
        bronze_storage=MinioBronzeObjectStorage.from_settings(settings),
    )


@router.post("", response_model=CreateUploadSessionResponse, status_code=status.HTTP_201_CREATED)
def create_upload_session(
    request: CreateUploadSessionRequest,
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> CreateUploadSessionResponse:
    """Создаёт upload session для одного experiment_id."""

    try:
        upload_session = service.create_session(
            experiment_id=request.experiment_id,
            expected_files=request.expected_files,
            client_id="web_ui",
        )
    except ExperimentAlreadyRegisteredError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "experiment.already_exists",
                "message": str(exc),
            },
        ) from exc
    except ActiveUploadSessionAlreadyExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "upload.session_already_active",
                "message": str(exc),
            },
        ) from exc
    except UploadSessionAlreadyExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "upload.session_conflict",
                "message": str(exc),
            },
        ) from exc
    except UploadSessionServiceError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "request.invalid_payload",
                "message": str(exc),
            },
        ) from exc

    return CreateUploadSessionResponse(
        upload_session_id=upload_session.upload_session_id,
        experiment_id=upload_session.experiment_id,
        status=upload_session.status,
        upload_base_url=f"/api/v1/uploads/{upload_session.upload_session_id}",
        expires_at=upload_session.expires_at.isoformat(),
    )


@router.put("/{upload_session_id}/files/{file_name}", response_model=UploadSessionStatusResponse)
async def upload_session_file(
    upload_session_id: Annotated[str, Path(min_length=1)],
    file_name: Annotated[str, Path(min_length=1)],
    request: Request,
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> UploadSessionStatusResponse:
    """Потоково записывает один файл в upload session."""

    try:
        target = service.prepare_file_upload(upload_session_id, file_name)
        await _write_request_body_to_file(
            request=request,
            target=target,
            max_size_bytes=settings.upload_max_size,
        )
        upload_session = service.record_uploaded_file(upload_session_id, file_name)
    except UploadFileTooLargeError as exc:
        raise HTTPException(
            status_code=413,
            detail={
                "code": "upload.file_too_large",
                "message": str(exc),
            },
        ) from exc
    except OSError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "upload.file_write_failed",
                "message": "Failed to write uploaded file",
            },
        ) from exc
    except UploadSessionNotFoundError as exc:
        raise _not_found(exc) from exc
    except UploadSessionStateConflictError as exc:
        raise _state_conflict(exc) from exc
    except UploadSessionServiceError as exc:
        raise _invalid_payload(exc) from exc

    return _status_response(upload_session)


@router.get("/{upload_session_id}", response_model=UploadSessionStatusResponse)
def get_upload_session(
    upload_session_id: Annotated[str, Path(min_length=1)],
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> UploadSessionStatusResponse:
    """Возвращает состояние upload session после reload страницы или UI polling."""

    try:
        upload_session = service.get_session(upload_session_id)
    except UploadSessionNotFoundError as exc:
        raise _not_found(exc) from exc

    return _status_response(upload_session)


@router.post("/{upload_session_id}/complete", response_model=CompleteUploadSessionResponse)
def complete_upload_session(
    upload_session_id: Annotated[str, Path(min_length=1)],
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> CompleteUploadSessionResponse:
    """Завершает upload session и синхронно запускает validation/promotion."""

    try:
        result = service.complete_session(upload_session_id)
    except UploadSessionNotFoundError as exc:
        raise _not_found(exc) from exc
    except UploadSessionIncompleteError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "upload.incomplete",
                "message": str(exc),
            },
        ) from exc
    except UploadObjectStorageUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "object_storage.unavailable",
                "message": str(exc),
            },
        ) from exc
    except UploadLocalCleanupError as exc:
        # Остаток локальной промо-папки от прошлой неудачной попытки не дали
        # удалить: приёмка ещё не состоялась, нужна ручная/async очистка стенда.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "upload.local_storage_cleanup_failed",
                "message": str(exc),
            },
        ) from exc
    except UploadSessionStateConflictError as exc:
        raise _state_conflict(exc) from exc

    return _completion_response(result)


@router.delete("/{upload_session_id}", response_model=UploadSessionStatusResponse)
def cancel_upload_session(
    upload_session_id: Annotated[str, Path(min_length=1)],
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> UploadSessionStatusResponse:
    """Отменяет upload session по пользовательскому действию."""

    try:
        upload_session = service.cancel_session(upload_session_id)
    except UploadSessionNotFoundError as exc:
        raise _not_found(exc) from exc
    except UploadSessionStateConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "upload.session_state_conflict",
                "message": str(exc),
            },
        ) from exc

    return _status_response(upload_session)


def _status_response(upload_session: UploadSessionView) -> UploadSessionStatusResponse:
    return UploadSessionStatusResponse(
        upload_session_id=upload_session.upload_session_id,
        experiment_id=upload_session.experiment_id,
        status=upload_session.status,
        expected_files=upload_session.expected_files,
        uploaded_files=upload_session.uploaded_files,
        expires_at=upload_session.expires_at.isoformat(),
    )


async def _write_request_body_to_file(
    *,
    request: Request,
    target: UploadFileTarget,
    max_size_bytes: int,
) -> None:
    bytes_written = 0

    _remove_if_exists(target.part_path)

    try:
        with target.part_path.open("wb") as destination:
            async for chunk in request.stream():
                if not chunk:
                    continue

                bytes_written += len(chunk)
                if bytes_written > max_size_bytes:
                    raise UploadFileTooLargeError(
                        f"upload file exceeds max size {max_size_bytes} bytes"
                    )

                destination.write(chunk)
    except Exception:
        _remove_if_exists(target.part_path)
        raise

    _replace_uploaded_file(target.part_path, target.final_path)


def _completion_response(result: UploadCompletionResult) -> CompleteUploadSessionResponse:
    validation_result = result.validation_result
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

    return CompleteUploadSessionResponse(
        upload_session_id=result.upload_session_id,
        experiment_id=result.experiment_id,
        status=result.status,
        accepted=result.accepted,
        validation_report_scope=_validation_report_scope(result),
        signal_size_bytes=None if validation_result is None else validation_result.signal_size_bytes,
        sample_count=None if validation_result is None else validation_result.sample_count,
        source_files=source_files,
        errors=[] if validation_result is None else [
            UploadValidationErrorDto(
                code=error.code,
                message=error.message,
                details=error.details,
            )
            for error in validation_result.errors
        ],
        warnings=[] if validation_result is None else validation_result.warnings,
    )


def _validation_report_scope(result: UploadCompletionResult) -> str | None:
    if result.validation_result is None:
        return None

    return "permanent" if result.accepted else "upload_tmp"


def _invalid_payload(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=422,
        detail={
            "code": "request.invalid_payload",
            "message": str(exc),
        },
    )


def _state_conflict(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={
            "code": "upload.session_state_conflict",
            "message": str(exc),
        },
    )


def _not_found(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "code": "upload.session_not_found",
            "message": str(exc),
        },
    )


def _remove_if_exists(path: FsPath) -> None:
    try:
        path.unlink()
    except (FileNotFoundError, PermissionError):
        return


def _replace_uploaded_file(part_path: FsPath, final_path: FsPath) -> None:
    try:
        part_path.replace(final_path)
    except PermissionError:
        # В production Linux `replace` остаётся атомарным. Этот fallback нужен
        # для Windows/sandbox окружения, где os.replace иногда запрещён.
        shutil.copy2(part_path, final_path)
        _remove_if_exists(part_path)
