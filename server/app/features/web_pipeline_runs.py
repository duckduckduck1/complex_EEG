"""Service-слой Web API для pipeline runs.

API не выполняет обработку синхронно. Он только создаёт запись `queued`, а
будущий `pipeline-worker` заберёт её из PostgreSQL polling-очереди.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import AuditEvent, Experiment, ExperimentEvent, PipelineArtifact, PipelineRun
from app.features.upload.session_service import generate_ulid


ACTIVE_PIPELINE_RUN_STATUSES = frozenset({"queued", "running"})
REPEAT_ALLOWED_EXPERIMENT_STATUSES = frozenset({"accepted", "processed", "processing_failed"})
MANUAL_REPEAT_TRIGGER_TYPE = "manual_repeat"
QUEUED_STATUS = "queued"


@dataclass(frozen=True)
class PipelineArtifactView:
    """Артефакт pipeline без filesystem path."""

    artifact_id: str
    name: str
    kind: str
    size_bytes: int | None
    media_type: str | None


@dataclass(frozen=True)
class PipelineRunView:
    """Публичное описание запуска pipeline."""

    pipeline_run_id: str
    status: str
    trigger_type: str
    pipeline_version: str | None
    started_at: datetime | None
    finished_at: datetime | None
    error_code: str | None
    error_message: str | None
    artifacts: list[PipelineArtifactView] = field(default_factory=list)


@dataclass(frozen=True)
class RepeatPipelineRunCommand:
    """Команда ручного повторного запуска."""

    experiment_id: str
    actor_user_id: UUID
    actor_username: str
    pipeline_version: str
    reason: str | None = None
    params: dict[str, object] = field(default_factory=dict)


class PipelineRunNotFoundError(ValueError):
    """Эксперимент для pipeline action не найден."""


class PipelineRunExperimentNotReadyError(ValueError):
    """Текущий статус эксперимента не допускает повторный запуск."""


class PipelineRunAlreadyActiveError(ValueError):
    """Для эксперимента уже есть queued/running запуск."""


class WebPipelineRunRepository(Protocol):
    """Минимальный контракт данных для Web pipeline API."""

    def get_experiment(self, experiment_id: str) -> Experiment | None:
        """Возвращает эксперимент по публичному experiment_id."""

    def list_pipeline_runs(self, experiment_id: str) -> list[PipelineRun]:
        """Возвращает запуски pipeline для эксперимента."""

    def list_pipeline_artifacts(self, pipeline_run_id: str) -> list[PipelineArtifact]:
        """Возвращает артефакты одного pipeline run."""

    def has_active_pipeline_run(self, experiment_id: str) -> bool:
        """True, если уже есть queued/running run."""

    def add_manual_repeat_run(
        self,
        *,
        experiment: Experiment,
        pipeline_run: PipelineRun,
        actor_user_id: UUID,
        actor_username: str,
        reason: str | None,
    ) -> None:
        """Добавляет pipeline run и события аудита в unit of work."""

    def commit(self) -> None:
        """Фиксирует изменения."""


class SqlAlchemyWebPipelineRunRepository:
    """SQLAlchemy-репозиторий для pipeline runs."""

    def __init__(self, db: Session) -> None:
        self._db = db

    def get_experiment(self, experiment_id: str) -> Experiment | None:
        statement = select(Experiment).where(Experiment.experiment_id == experiment_id)
        return self._db.execute(statement).scalars().first()

    def list_pipeline_runs(self, experiment_id: str) -> list[PipelineRun]:
        statement = (
            select(PipelineRun)
            .where(PipelineRun.experiment_id == experiment_id)
            .order_by(PipelineRun.created_at.desc())
        )
        return list(self._db.execute(statement).scalars())

    def list_pipeline_artifacts(self, pipeline_run_id: str) -> list[PipelineArtifact]:
        statement = (
            select(PipelineArtifact)
            .where(PipelineArtifact.pipeline_run_id == pipeline_run_id)
            .order_by(PipelineArtifact.created_at.asc())
        )
        return list(self._db.execute(statement).scalars())

    def has_active_pipeline_run(self, experiment_id: str) -> bool:
        statement = (
            select(PipelineRun.id)
            .where(
                PipelineRun.experiment_id == experiment_id,
                PipelineRun.status.in_(ACTIVE_PIPELINE_RUN_STATUSES),
            )
            .limit(1)
        )
        return self._db.execute(statement).first() is not None

    def add_manual_repeat_run(
        self,
        *,
        experiment: Experiment,
        pipeline_run: PipelineRun,
        actor_user_id: UUID,
        actor_username: str,
        reason: str | None,
    ) -> None:
        self._db.add(pipeline_run)
        self._db.add(
            ExperimentEvent(
                experiment_id=experiment.experiment_id,
                event_type="pipeline_repeat_requested",
                from_status=experiment.status,
                to_status=experiment.status,
                message=reason or "Manual repeat pipeline run queued",
                details={
                    "pipeline_run_id": pipeline_run.id,
                    "actor_username": actor_username,
                },
            )
        )
        self._db.add(
            AuditEvent(
                actor_user_id=actor_user_id,
                event_type="pipeline.repeat_requested",
                experiment_id=experiment.experiment_id,
                pipeline_run_id=pipeline_run.id,
                details={
                    "reason": reason,
                    "trigger_type": pipeline_run.trigger_type,
                },
            )
        )

    def commit(self) -> None:
        self._db.commit()


class WebPipelineRunService:
    """Use cases для чтения и ручной постановки pipeline runs в очередь."""

    def __init__(self, repository: WebPipelineRunRepository) -> None:
        self._repository = repository

    def list_pipeline_runs(self, experiment_id: str) -> list[PipelineRunView]:
        """Возвращает runs одного эксперимента."""

        experiment = self._get_existing_experiment(experiment_id)

        return [
            self._to_view(pipeline_run)
            for pipeline_run in self._repository.list_pipeline_runs(experiment.experiment_id)
        ]

    def create_manual_repeat_run(self, command: RepeatPipelineRunCommand) -> PipelineRunView:
        """Создаёт queued run для ручного повторного запуска."""

        experiment = self._get_existing_experiment(command.experiment_id)
        if experiment.status not in REPEAT_ALLOWED_EXPERIMENT_STATUSES:
            raise PipelineRunExperimentNotReadyError(
                f"experiment status {experiment.status} does not allow repeat pipeline run"
            )

        if self._repository.has_active_pipeline_run(experiment.experiment_id):
            raise PipelineRunAlreadyActiveError(
                "experiment already has active queued or running pipeline run"
            )

        pipeline_run = PipelineRun(
            id=generate_ulid(),
            experiment_id=experiment.experiment_id,
            status=QUEUED_STATUS,
            trigger_type=MANUAL_REPEAT_TRIGGER_TYPE,
            pipeline_version=command.pipeline_version,
            params_json=command.params,
        )

        self._repository.add_manual_repeat_run(
            experiment=experiment,
            pipeline_run=pipeline_run,
            actor_user_id=command.actor_user_id,
            actor_username=command.actor_username,
            reason=command.reason,
        )
        self._repository.commit()

        return self._to_view(pipeline_run)

    def _get_existing_experiment(self, experiment_id: str) -> Experiment:
        experiment = self._repository.get_experiment(experiment_id)
        if experiment is None:
            raise PipelineRunNotFoundError("experiment was not found")
        return experiment

    def _to_view(self, pipeline_run: PipelineRun) -> PipelineRunView:
        return PipelineRunView(
            pipeline_run_id=pipeline_run.id,
            status=pipeline_run.status,
            trigger_type=pipeline_run.trigger_type,
            pipeline_version=pipeline_run.pipeline_version,
            started_at=pipeline_run.started_at,
            finished_at=pipeline_run.finished_at,
            error_code=pipeline_run.error_code,
            error_message=pipeline_run.error_message,
            artifacts=[
                PipelineArtifactView(
                    artifact_id=artifact.id,
                    name=artifact.name,
                    kind=artifact.kind,
                    size_bytes=artifact.size_bytes,
                    media_type=artifact.media_type,
                )
                for artifact in self._repository.list_pipeline_artifacts(pipeline_run.id)
            ],
        )
