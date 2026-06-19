"""HTTP API для upload sessions.

Это первый production-like слой upload lifecycle. Здесь ещё нет настоящей
загрузки файлов и web-auth, но уже есть стабильные API-контракты для создания,
проверки статуса и отмены upload session.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db_session
from app.features.upload.session_service import (
    DEFAULT_UPLOAD_FILES,
    UploadSessionAlreadyExistsError,
    UploadSessionNotFoundError,
    UploadSessionService,
    UploadSessionServiceError,
    UploadSessionStateConflictError,
    UploadSessionView,
    SqlAlchemyUploadSessionRepository,
)


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


def get_upload_session_service(
    db: Annotated[Session, Depends(get_db_session)],
) -> UploadSessionService:
    """Собирает service-слой для HTTP request.

    Сейчас client identity ещё не приходит из web-auth. Поэтому service получает
    технический `client_id = web_ui` внутри endpoint'а. Когда появится auth layer,
    здесь появится dependency текущего пользователя.
    """

    return UploadSessionService(
        repository=SqlAlchemyUploadSessionRepository(db),
        upload_tmp_root=settings.upload_tmp_dir,
        ttl_hours=settings.upload_session_ttl_hours,
    )


@router.post("", response_model=CreateUploadSessionResponse, status_code=status.HTTP_201_CREATED)
def create_upload_session(
    request: CreateUploadSessionRequest,
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> CreateUploadSessionResponse:
    """Создаёт upload session для одного experiment_id."""

    try:
        upload_session = service.create_session(
            experiment_id=request.experiment_id,
            expected_files=request.expected_files,
            client_id="web_ui",
        )
    except UploadSessionAlreadyExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "upload.session_already_active",
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


@router.get("/{upload_session_id}", response_model=UploadSessionStatusResponse)
def get_upload_session(
    upload_session_id: Annotated[str, Path(min_length=1)],
    service: Annotated[UploadSessionService, Depends(get_upload_session_service)],
) -> UploadSessionStatusResponse:
    """Возвращает состояние upload session после reload страницы или UI polling."""

    try:
        upload_session = service.get_session(upload_session_id)
    except UploadSessionNotFoundError as exc:
        raise _not_found(exc) from exc

    return _status_response(upload_session)


@router.delete("/{upload_session_id}", response_model=UploadSessionStatusResponse)
def cancel_upload_session(
    upload_session_id: Annotated[str, Path(min_length=1)],
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


def _not_found(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "code": "upload.session_not_found",
            "message": str(exc),
        },
    )
