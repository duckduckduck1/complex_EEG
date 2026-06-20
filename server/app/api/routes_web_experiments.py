"""Web endpoints для списка и карточки эксперимента."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps_auth import require_current_user
from app.db.session import get_db_session
from app.features.auth import CurrentUser
from app.features.web_experiments import (
    ExperimentListFilters,
    ExperimentSort,
    SqlAlchemyWebExperimentRepository,
    WebExperimentInvalidFilterError,
    WebExperimentNotFoundError,
    WebExperimentService,
)


router = APIRouter(prefix="/api/v1/web/experiments", tags=["web-experiments"])


class ErrorResponse(BaseModel):
    """Безопасная ошибка для UI."""

    code: str
    message: str | None = None


class ExperimentListItemResponse(BaseModel):
    """Одна строка таблицы экспериментов."""

    experiment_id: str
    display_name: str
    status: str
    uploaded_at: datetime | None
    accepted_at: datetime | None
    updated_at: datetime
    last_pipeline_status: str | None
    last_error: ErrorResponse | None


class ExperimentListResponse(BaseModel):
    """Страница списка экспериментов."""

    items: list[ExperimentListItemResponse]
    limit: int
    offset: int
    total: int


class SourceFileResponse(BaseModel):
    """Публичное описание исходного файла без server paths и MinIO object keys."""

    name: str
    size_bytes: int
    download_allowed: bool


class ValidationResponse(BaseModel):
    """Состояние validation для карточки эксперимента."""

    status: str
    error: ErrorResponse | None


class PipelineArtifactResponse(BaseModel):
    """Артефакт pipeline без filesystem path."""

    artifact_id: str
    name: str
    kind: str
    size_bytes: int | None
    media_type: str | None


class PipelineRunResponse(BaseModel):
    """Запуск pipeline в карточке эксперимента."""

    pipeline_run_id: str
    status: str
    trigger_type: str
    pipeline_version: str | None
    started_at: datetime | None
    finished_at: datetime | None
    error_code: str | None
    error_message: str | None
    artifacts: list[PipelineArtifactResponse] = Field(default_factory=list)


class ExperimentEventResponse(BaseModel):
    """Событие жизненного цикла эксперимента."""

    event_type: str
    from_status: str | None
    to_status: str | None
    message: str | None
    created_at: datetime


class ExperimentDetailResponse(BaseModel):
    """Карточка эксперимента для Web UI."""

    experiment_id: str
    display_name: str
    status: str
    metadata: dict[str, object]
    uploaded_at: datetime | None
    accepted_at: datetime | None
    updated_at: datetime
    validation: ValidationResponse
    source_files: list[SourceFileResponse]
    pipeline_runs: list[PipelineRunResponse]
    events: list[ExperimentEventResponse]


def get_web_experiment_service(
    db: Annotated[Session, Depends(get_db_session)],
) -> WebExperimentService:
    """Собирает service чтения экспериментов для одного HTTP request."""

    return WebExperimentService(
        repository=SqlAlchemyWebExperimentRepository(db),
    )


@router.get("", response_model=ExperimentListResponse)
def list_experiments(
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[WebExperimentService, Depends(get_web_experiment_service)],
    status_filter: Annotated[str | None, Query(alias="status", max_length=64)] = None,
    date_from: Annotated[datetime | None, Query()] = None,
    date_to: Annotated[datetime | None, Query()] = None,
    search: Annotated[str | None, Query(max_length=128)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    sort: Annotated[ExperimentSort, Query()] = "uploaded_at_desc",
) -> ExperimentListResponse:
    """Возвращает страницу экспериментов для таблицы Web UI."""

    try:
        page = service.list_experiments(
            ExperimentListFilters(
                status=status_filter,
                date_from=date_from,
                date_to=date_to,
                search=search,
                limit=limit,
                offset=offset,
                sort=sort,
            )
        )
    except WebExperimentInvalidFilterError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "request.invalid_query",
                "message": str(exc),
            },
        ) from exc

    return ExperimentListResponse(
        items=[
            ExperimentListItemResponse(
                experiment_id=item.experiment_id,
                display_name=item.display_name,
                status=item.status,
                uploaded_at=item.uploaded_at,
                accepted_at=item.accepted_at,
                updated_at=item.updated_at,
                last_pipeline_status=item.last_pipeline_status,
                last_error=_error_response(item.last_error),
            )
            for item in page.items
        ],
        limit=page.limit,
        offset=page.offset,
        total=page.total,
    )


@router.get("/{experiment_id}", response_model=ExperimentDetailResponse)
def get_experiment_detail(
    experiment_id: Annotated[str, Path(min_length=1, max_length=64)],
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[WebExperimentService, Depends(get_web_experiment_service)],
) -> ExperimentDetailResponse:
    """Возвращает подробную карточку эксперимента."""

    try:
        detail = service.get_experiment_detail(experiment_id)
    except WebExperimentNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "experiment.not_found",
                "message": str(exc),
            },
        ) from exc

    return ExperimentDetailResponse(
        experiment_id=detail.experiment_id,
        display_name=detail.display_name,
        status=detail.status,
        metadata=detail.metadata,
        uploaded_at=detail.uploaded_at,
        accepted_at=detail.accepted_at,
        updated_at=detail.updated_at,
        validation=ValidationResponse(
            status=detail.validation.status,
            error=_error_response(detail.validation.error),
        ),
        source_files=[
            SourceFileResponse(
                name=source_file.name,
                size_bytes=source_file.size_bytes,
                download_allowed=source_file.download_allowed,
            )
            for source_file in detail.source_files
        ],
        pipeline_runs=[
            PipelineRunResponse(
                pipeline_run_id=pipeline_run.pipeline_run_id,
                status=pipeline_run.status,
                trigger_type=pipeline_run.trigger_type,
                pipeline_version=pipeline_run.pipeline_version,
                started_at=pipeline_run.started_at,
                finished_at=pipeline_run.finished_at,
                error_code=pipeline_run.error_code,
                error_message=pipeline_run.error_message,
                artifacts=[
                    PipelineArtifactResponse(
                        artifact_id=artifact.artifact_id,
                        name=artifact.name,
                        kind=artifact.kind,
                        size_bytes=artifact.size_bytes,
                        media_type=artifact.media_type,
                    )
                    for artifact in pipeline_run.artifacts
                ],
            )
            for pipeline_run in detail.pipeline_runs
        ],
        events=[
            ExperimentEventResponse(
                event_type=event.event_type,
                from_status=event.from_status,
                to_status=event.to_status,
                message=event.message,
                created_at=event.created_at,
            )
            for event in detail.events
        ],
    )


def _error_response(error: object | None) -> ErrorResponse | None:
    if error is None:
        return None

    return ErrorResponse(
        code=getattr(error, "code"),
        message=getattr(error, "message"),
    )
