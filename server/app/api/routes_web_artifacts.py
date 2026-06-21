"""Web endpoints для скачивания pipeline artifacts."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps_auth import require_current_user
from app.core.config import settings
from app.db.session import get_db_session
from app.features.auth import CurrentUser
from app.features.web_artifacts import (
    ArtifactDownloadNotFoundError,
    ArtifactFileMissingError,
    ArtifactPathUnsafeError,
    SqlAlchemyWebArtifactRepository,
    WebArtifactService,
)


router = APIRouter(prefix="/api/v1/web/experiments", tags=["web-artifacts"])


def get_web_artifact_service(
    db: Annotated[Session, Depends(get_db_session)],
) -> WebArtifactService:
    """Собирает service скачивания artifacts для одного HTTP request."""

    return WebArtifactService(
        repository=SqlAlchemyWebArtifactRepository(db),
        pipeline_results_root=settings.pipeline_results_dir,
    )


@router.get("/{experiment_id}/artifacts/{artifact_id}")
def download_artifact(
    experiment_id: Annotated[str, Path(min_length=1, max_length=64)],
    artifact_id: Annotated[str, Path(min_length=1, max_length=64)],
    _current_user: Annotated[CurrentUser, Depends(require_current_user)],
    service: Annotated[WebArtifactService, Depends(get_web_artifact_service)],
) -> FileResponse:
    """Отдаёт файл artifact после проверки принадлежности и безопасного пути."""

    try:
        artifact = service.prepare_artifact_download(
            experiment_id=experiment_id,
            artifact_id=artifact_id,
        )
    except ArtifactDownloadNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "artifact.not_found",
                "message": str(exc),
            },
        ) from exc
    except ArtifactFileMissingError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "artifact.file_missing",
                "message": str(exc),
            },
        ) from exc
    except ArtifactPathUnsafeError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "artifact.path_unsafe",
                "message": str(exc),
            },
        ) from exc

    return FileResponse(
        path=artifact.file_path,
        media_type=artifact.media_type,
        filename=artifact.file_name,
    )
