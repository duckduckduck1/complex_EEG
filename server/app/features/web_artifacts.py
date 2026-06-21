"""Service-слой скачивания pipeline artifacts.

Сервер никогда не принимает filesystem path от клиента. Web UI передаёт только
`artifact_id`, а путь к файлу строится из доверенного корня `PIPELINE_RESULTS_DIR`
и данных БД с обязательной проверкой выхода за пределы run-директории.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import Experiment, PipelineArtifact


@dataclass(frozen=True)
class ArtifactDownload:
    """Безопасно подготовленный файл для HTTP-ответа."""

    file_path: Path
    file_name: str
    media_type: str


class ArtifactDownloadNotFoundError(ValueError):
    """Experiment или artifact не найден."""


class ArtifactFileMissingError(ValueError):
    """Запись artifact есть, но файла на диске нет."""


class ArtifactPathUnsafeError(ValueError):
    """relative_path artifact выходит за пределы директории pipeline run."""


class WebArtifactRepository(Protocol):
    """Минимальный контракт чтения artifact metadata."""

    def experiment_exists(self, experiment_id: str) -> bool:
        """True, если experiment_id существует."""

    def get_artifact(self, experiment_id: str, artifact_id: str) -> PipelineArtifact | None:
        """Возвращает artifact, принадлежащий experiment_id."""


class SqlAlchemyWebArtifactRepository:
    """SQLAlchemy-репозиторий для artifact download endpoint."""

    def __init__(self, db: Session) -> None:
        self._db = db

    def experiment_exists(self, experiment_id: str) -> bool:
        statement = select(Experiment.id).where(Experiment.experiment_id == experiment_id).limit(1)
        return self._db.execute(statement).first() is not None

    def get_artifact(self, experiment_id: str, artifact_id: str) -> PipelineArtifact | None:
        statement = select(PipelineArtifact).where(
            PipelineArtifact.id == artifact_id,
            PipelineArtifact.experiment_id == experiment_id,
        )
        return self._db.execute(statement).scalars().first()


class WebArtifactService:
    """Use case скачивания pipeline artifact."""

    def __init__(self, *, repository: WebArtifactRepository, pipeline_results_root: str | Path) -> None:
        self._repository = repository
        self._pipeline_results_root = Path(pipeline_results_root)

    def prepare_artifact_download(self, *, experiment_id: str, artifact_id: str) -> ArtifactDownload:
        """Проверяет artifact и возвращает безопасный путь к файлу."""

        if not self._repository.experiment_exists(experiment_id):
            raise ArtifactDownloadNotFoundError("experiment was not found")

        artifact = self._repository.get_artifact(experiment_id, artifact_id)
        if artifact is None:
            raise ArtifactDownloadNotFoundError("artifact was not found")

        file_path = self._resolve_artifact_path(artifact)
        if not file_path.is_file():
            raise ArtifactFileMissingError("artifact file is missing")

        return ArtifactDownload(
            file_path=file_path,
            file_name=artifact.name,
            media_type=artifact.media_type or "application/octet-stream",
        )

    def _resolve_artifact_path(self, artifact: PipelineArtifact) -> Path:
        relative_path = Path(artifact.relative_path)
        if relative_path.is_absolute():
            raise ArtifactPathUnsafeError("artifact relative_path must not be absolute")

        run_dir = (
            self._pipeline_results_root
            / artifact.experiment_id
            / "runs"
            / artifact.pipeline_run_id
        )
        candidate_path = run_dir / relative_path

        resolved_run_dir = run_dir.resolve()
        resolved_candidate_path = candidate_path.resolve()

        try:
            resolved_candidate_path.relative_to(resolved_run_dir)
        except ValueError as exc:
            raise ArtifactPathUnsafeError(
                "artifact relative_path escapes pipeline run directory"
            ) from exc

        return resolved_candidate_path
