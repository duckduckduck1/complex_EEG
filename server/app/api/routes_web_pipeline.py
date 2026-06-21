"""Web endpoints для pipeline runs."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps_auth import require_current_user
from app.core.config import settings
from app.db.session import get_db_session
from app.features.auth import CurrentUser
from app.features.web_pipeline_runs import (
    PipelineRunAlreadyActiveError,
    PipelineRunExperimentNotReadyError,
    PipelineRunNotFoundError,
    RepeatPipelineRunCommand,
    SqlAlchemyWebPipelineRunRepository,
    WebPipelineRunService,
)


router = APIRouter(prefix="/api/v1/web/experiments", tags=["web-pipeline"])
PIPELINE_OPERATOR_ROLES = frozenset({"operator", "admin"})


class PipelineArtifactResponse(BaseModel):
    """Артефакт pipeline без filesystem path."""

    artifact_id: str
    name: str
    kind: str
    size_bytes: int | None
    media_type: str | None


class PipelineRunResponse(BaseModel):
    """Публичное описание запуска pipeline."""

    pipeline_run_id: str
    status: str
    trigger_type: str
    pipeline_version: str | None
    started_at: datetime | None
    finished_at: datetime | None
    error_code: str | None
    error_message: str | None
    artifacts: list[PipelineArtifactResponse] = Field(default_factory=list)


class PipelineRunListResponse(BaseModel):
    """Список запусков pipeline для одного эксперимента."""

    items: list[PipelineRunResponse]


class CreateRepeatPipelineRunRequest(BaseModel):
    """Payload ручного повторного запуска pipeline."""

    reason: str | None = Field(default=None, max_length=512)
    params: dict[str, object] = Field(default_factory=dict)


def get_web_pipeline_run_service(
    db: Annotated[Session, Depends(get_db_session)],
) -> WebPipelineRunService:
    """Собирает service pipeline runs для одного HTTP request."""

    return WebPipelineRunService(
        repository=SqlAlchemyWebPipelineRunRepository(db),
    )


def require_pipeline_operator(
    current_user: Annotated[CurrentUser, Depends(require_current_user)],
) -> CurrentUser:
    """Допускает к mutating pipeline actions только operator/admin."""

    if current_user.role not in PIPELINE_OPERATOR_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "auth.forbidden",
                "message": "Current user cannot start pipeline runs",
            },
        )

    return current_user


@router.get("/{experiment_id}/pipeline-runs", response_model=PipelineRunListResponse)
def list_pipeline_runs(
    experiment_id: Annotated[str, Path(min_length=1, max_length=64)],
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[WebPipelineRunService, Depends(get_web_pipeline_run_service)],
) -> PipelineRunListResponse:
    """Возвращает все pipeline runs одного эксперимента."""

    try:
        pipeline_runs = service.list_pipeline_runs(experiment_id)
    except PipelineRunNotFoundError as exc:
        raise _experiment_not_found(exc) from exc

    return PipelineRunListResponse(
        items=[_pipeline_run_response(pipeline_run) for pipeline_run in pipeline_runs],
    )


@router.post(
    "/{experiment_id}/pipeline-runs",
    response_model=PipelineRunResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_repeat_pipeline_run(
    experiment_id: Annotated[str, Path(min_length=1, max_length=64)],
    request: CreateRepeatPipelineRunRequest,
    current_user: Annotated[CurrentUser, Depends(require_pipeline_operator)],
    service: Annotated[WebPipelineRunService, Depends(get_web_pipeline_run_service)],
) -> PipelineRunResponse:
    """Ставит ручной повторный запуск pipeline в очередь."""

    try:
        pipeline_run = service.create_manual_repeat_run(
            RepeatPipelineRunCommand(
                experiment_id=experiment_id,
                actor_user_id=current_user.id,
                actor_username=current_user.username,
                pipeline_version=settings.pipeline_version,
                reason=request.reason,
                params=request.params,
            )
        )
    except PipelineRunNotFoundError as exc:
        raise _experiment_not_found(exc) from exc
    except PipelineRunExperimentNotReadyError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "pipeline.experiment_not_ready",
                "message": str(exc),
            },
        ) from exc
    except PipelineRunAlreadyActiveError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "pipeline.active_run_exists",
                "message": str(exc),
            },
        ) from exc

    return _pipeline_run_response(pipeline_run)


def _pipeline_run_response(pipeline_run: object) -> PipelineRunResponse:
    return PipelineRunResponse(
        pipeline_run_id=getattr(pipeline_run, "pipeline_run_id"),
        status=getattr(pipeline_run, "status"),
        trigger_type=getattr(pipeline_run, "trigger_type"),
        pipeline_version=getattr(pipeline_run, "pipeline_version"),
        started_at=getattr(pipeline_run, "started_at"),
        finished_at=getattr(pipeline_run, "finished_at"),
        error_code=getattr(pipeline_run, "error_code"),
        error_message=getattr(pipeline_run, "error_message"),
        artifacts=[
            PipelineArtifactResponse(
                artifact_id=getattr(artifact, "artifact_id"),
                name=getattr(artifact, "name"),
                kind=getattr(artifact, "kind"),
                size_bytes=getattr(artifact, "size_bytes"),
                media_type=getattr(artifact, "media_type"),
            )
            for artifact in getattr(pipeline_run, "artifacts")
        ],
    )


def _experiment_not_found(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "code": "experiment.not_found",
            "message": str(exc),
        },
    )
