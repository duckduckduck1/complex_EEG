"""Service-слой фонового pipeline worker.

Worker берёт `queued` задачи из PostgreSQL, переводит их в `running`, пишет
heartbeat и завершает как `succeeded` или `failed`. Реальный анализ EEG-сигнала
будет добавлен позже; сейчас executor создаёт минимальный result manifest.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import Experiment, ExperimentEvent, PipelineRun


PIPELINE_STATUS_QUEUED = "queued"
PIPELINE_STATUS_RUNNING = "running"
PIPELINE_STATUS_SUCCEEDED = "succeeded"
PIPELINE_STATUS_FAILED = "failed"
EXPERIMENT_STATUS_PROCESSING = "processing"
EXPERIMENT_STATUS_PROCESSED = "processed"
EXPERIMENT_STATUS_PROCESSING_FAILED = "processing_failed"
PIPELINE_STUCK_ERROR_CODE = "pipeline.run_stuck"
PIPELINE_STUCK_ERROR_MESSAGE = "Pipeline run exceeded heartbeat or max duration limit"
PIPELINE_SKELETON_ERROR_CODE = "pipeline.skeleton_failed"


@dataclass(frozen=True)
class PipelineRunJob:
    """Задача, которую worker забрал из очереди."""

    pipeline_run_id: str
    experiment_id: str
    trigger_type: str
    pipeline_version: str | None
    params: dict[str, object] = field(default_factory=dict)
    started_at: datetime | None = None


@dataclass(frozen=True)
class PipelineExecutionResult:
    """Результат работы executor'а до записи статуса в БД."""

    result_dir: Path
    manifest_path: Path


@dataclass(frozen=True)
class PipelineWorkerCycleResult:
    """Итог одного worker cycle."""

    claimed_run_id: str | None
    status: str
    stuck_failed_count: int = 0
    message: str | None = None


class PipelineWorkerRepository(Protocol):
    """Минимальный контракт БД, который нужен worker service."""

    def fail_stuck_runs(
        self,
        *,
        now: datetime,
        heartbeat_timeout: timedelta,
        max_run_duration: timedelta,
    ) -> int:
        """Переводит зависшие running runs в failed."""

    def claim_next_queued_run(self, *, now: datetime) -> PipelineRunJob | None:
        """Транзакционно берёт следующий queued run и переводит его в running."""

    def update_heartbeat(self, pipeline_run_id: str, *, heartbeat_at: datetime) -> None:
        """Обновляет heartbeat running run."""

    def mark_succeeded(
        self,
        pipeline_run_id: str,
        *,
        result_path: Path,
        finished_at: datetime,
    ) -> None:
        """Завершает run как succeeded."""

    def mark_failed(
        self,
        pipeline_run_id: str,
        *,
        error_code: str,
        error_message: str,
        finished_at: datetime,
    ) -> None:
        """Завершает run как failed."""


class PipelineRunExecutor(Protocol):
    """Исполнитель одной pipeline-задачи."""

    def execute(
        self,
        job: PipelineRunJob,
        *,
        result_dir: Path,
        heartbeat: Callable[[], None],
    ) -> PipelineExecutionResult:
        """Выполняет обработку и возвращает путь к результатам."""


class SqlAlchemyPipelineWorkerRepository:
    """SQLAlchemy-репозиторий worker'а.

    `claim_next_queued_run` использует `FOR UPDATE SKIP LOCKED`: это позволяет
    запустить несколько worker-процессов и не забрать одну задачу дважды.
    """

    def __init__(self, db: Session) -> None:
        self._db = db

    def fail_stuck_runs(
        self,
        *,
        now: datetime,
        heartbeat_timeout: timedelta,
        max_run_duration: timedelta,
    ) -> int:
        statement = select(PipelineRun).where(PipelineRun.status == PIPELINE_STATUS_RUNNING)
        stuck_runs = [
            pipeline_run
            for pipeline_run in self._db.execute(statement).scalars()
            if _is_stuck(
                pipeline_run,
                now=now,
                heartbeat_timeout=heartbeat_timeout,
                max_run_duration=max_run_duration,
            )
        ]

        for pipeline_run in stuck_runs:
            self._mark_run_failed(
                pipeline_run,
                error_code=PIPELINE_STUCK_ERROR_CODE,
                error_message=PIPELINE_STUCK_ERROR_MESSAGE,
                finished_at=now,
            )

        if stuck_runs:
            self._db.commit()

        return len(stuck_runs)

    def claim_next_queued_run(self, *, now: datetime) -> PipelineRunJob | None:
        statement = (
            select(PipelineRun)
            .where(PipelineRun.status == PIPELINE_STATUS_QUEUED)
            .order_by(PipelineRun.created_at.asc())
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        pipeline_run = self._db.execute(statement).scalars().first()
        if pipeline_run is None:
            return None

        pipeline_run.status = PIPELINE_STATUS_RUNNING
        pipeline_run.started_at = now
        pipeline_run.heartbeat_at = now
        self._set_experiment_status(
            experiment_id=pipeline_run.experiment_id,
            status=EXPERIMENT_STATUS_PROCESSING,
            event_type="pipeline_started",
            message="Pipeline run started",
        )

        job = _to_job(pipeline_run)
        self._db.commit()
        return job

    def update_heartbeat(self, pipeline_run_id: str, *, heartbeat_at: datetime) -> None:
        pipeline_run = self._get_run(pipeline_run_id)
        pipeline_run.heartbeat_at = heartbeat_at
        self._db.commit()

    def mark_succeeded(
        self,
        pipeline_run_id: str,
        *,
        result_path: Path,
        finished_at: datetime,
    ) -> None:
        pipeline_run = self._get_run(pipeline_run_id)
        pipeline_run.status = PIPELINE_STATUS_SUCCEEDED
        pipeline_run.result_path = str(result_path)
        pipeline_run.finished_at = finished_at
        pipeline_run.heartbeat_at = finished_at
        self._set_experiment_status(
            experiment_id=pipeline_run.experiment_id,
            status=EXPERIMENT_STATUS_PROCESSED,
            event_type="pipeline_succeeded",
            message="Pipeline run succeeded",
        )
        self._db.commit()

    def mark_failed(
        self,
        pipeline_run_id: str,
        *,
        error_code: str,
        error_message: str,
        finished_at: datetime,
    ) -> None:
        pipeline_run = self._get_run(pipeline_run_id)
        self._mark_run_failed(
            pipeline_run,
            error_code=error_code,
            error_message=error_message,
            finished_at=finished_at,
        )
        self._db.commit()

    def _get_run(self, pipeline_run_id: str) -> PipelineRun:
        pipeline_run = self._db.get(PipelineRun, pipeline_run_id)
        if pipeline_run is None:
            raise ValueError(f"pipeline run {pipeline_run_id} was not found")
        return pipeline_run

    def _mark_run_failed(
        self,
        pipeline_run: PipelineRun,
        *,
        error_code: str,
        error_message: str,
        finished_at: datetime,
    ) -> None:
        pipeline_run.status = PIPELINE_STATUS_FAILED
        pipeline_run.error_code = error_code
        pipeline_run.error_message = error_message
        pipeline_run.finished_at = finished_at
        pipeline_run.heartbeat_at = finished_at
        self._set_experiment_status(
            experiment_id=pipeline_run.experiment_id,
            status=EXPERIMENT_STATUS_PROCESSING_FAILED,
            event_type="pipeline_failed",
            message=error_message,
        )

    def _set_experiment_status(
        self,
        *,
        experiment_id: str,
        status: str,
        event_type: str,
        message: str,
    ) -> None:
        statement = select(Experiment).where(Experiment.experiment_id == experiment_id)
        experiment = self._db.execute(statement).scalars().first()
        from_status = None

        if experiment is not None:
            from_status = experiment.status
            experiment.status = status

        self._db.add(
            ExperimentEvent(
                experiment_id=experiment_id,
                event_type=event_type,
                from_status=from_status,
                to_status=status,
                message=message,
            )
        )


class SkeletonPipelineRunExecutor:
    """Временный executor без реального анализа EEG-сигнала.

    Он создаёт структуру результата и `result_manifest.json`, чтобы весь путь
    queue -> worker -> results -> status уже можно было запускать на VM.
    """

    def execute(
        self,
        job: PipelineRunJob,
        *,
        result_dir: Path,
        heartbeat: Callable[[], None],
    ) -> PipelineExecutionResult:
        logs_dir = result_dir / "logs"
        artifacts_dir = result_dir / "artifacts"
        logs_dir.mkdir(parents=True, exist_ok=True)
        artifacts_dir.mkdir(parents=True, exist_ok=True)

        # Даже skeleton делает heartbeat: так мы проверяем полный контракт worker'а
        # до появления долгой обработки сигнала.
        heartbeat()

        manifest_path = result_dir / "result_manifest.json"
        manifest = {
            "pipeline_run_id": job.pipeline_run_id,
            "experiment_id": job.experiment_id,
            "pipeline_version": job.pipeline_version,
            "status": PIPELINE_STATUS_SUCCEEDED,
            "started_at": _isoformat(job.started_at),
            "finished_at": _isoformat(datetime.now(UTC)),
            "params": job.params,
            "artifacts": [],
            "warnings": ["pipeline skeleton did not run EEG signal analysis"],
            "errors": [],
        }
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

        return PipelineExecutionResult(
            result_dir=result_dir,
            manifest_path=manifest_path,
        )


class PipelineWorkerService:
    """Один цикл работы pipeline worker."""

    def __init__(
        self,
        *,
        repository: PipelineWorkerRepository,
        pipeline_results_root: str | Path,
        stuck_heartbeat_minutes: int,
        max_run_duration_hours: int,
        executor: PipelineRunExecutor | None = None,
        now: datetime | None = None,
    ) -> None:
        self._repository = repository
        self._pipeline_results_root = Path(pipeline_results_root)
        self._stuck_heartbeat_minutes = stuck_heartbeat_minutes
        self._max_run_duration_hours = max_run_duration_hours
        self._executor = executor or SkeletonPipelineRunExecutor()
        self._now = now

    def run_once(self) -> PipelineWorkerCycleResult:
        """Выполняет один poll cycle worker'а."""

        now = self._current_time()
        stuck_failed_count = self._repository.fail_stuck_runs(
            now=now,
            heartbeat_timeout=timedelta(minutes=self._stuck_heartbeat_minutes),
            max_run_duration=timedelta(hours=self._max_run_duration_hours),
        )

        job = self._repository.claim_next_queued_run(now=now)
        if job is None:
            return PipelineWorkerCycleResult(
                claimed_run_id=None,
                status="idle",
                stuck_failed_count=stuck_failed_count,
            )

        try:
            execution_result = self._executor.execute(
                job,
                result_dir=self._result_dir(job),
                heartbeat=lambda: self._repository.update_heartbeat(
                    job.pipeline_run_id,
                    heartbeat_at=self._current_time(),
                ),
            )
        except Exception as exc:
            self._repository.mark_failed(
                job.pipeline_run_id,
                error_code=PIPELINE_SKELETON_ERROR_CODE,
                error_message=str(exc),
                finished_at=self._current_time(),
            )
            return PipelineWorkerCycleResult(
                claimed_run_id=job.pipeline_run_id,
                status=PIPELINE_STATUS_FAILED,
                stuck_failed_count=stuck_failed_count,
                message=str(exc),
            )

        self._repository.mark_succeeded(
            job.pipeline_run_id,
            result_path=execution_result.result_dir,
            finished_at=self._current_time(),
        )
        return PipelineWorkerCycleResult(
            claimed_run_id=job.pipeline_run_id,
            status=PIPELINE_STATUS_SUCCEEDED,
            stuck_failed_count=stuck_failed_count,
            message=str(execution_result.manifest_path),
        )

    def _result_dir(self, job: PipelineRunJob) -> Path:
        return (
            self._pipeline_results_root
            / job.experiment_id
            / "runs"
            / job.pipeline_run_id
        )

    def _current_time(self) -> datetime:
        return self._now or datetime.now(UTC)


def _to_job(pipeline_run: PipelineRun) -> PipelineRunJob:
    return PipelineRunJob(
        pipeline_run_id=pipeline_run.id,
        experiment_id=pipeline_run.experiment_id,
        trigger_type=pipeline_run.trigger_type,
        pipeline_version=pipeline_run.pipeline_version,
        params=pipeline_run.params_json or {},
        started_at=pipeline_run.started_at,
    )


def _is_stuck(
    pipeline_run: PipelineRun,
    *,
    now: datetime,
    heartbeat_timeout: timedelta,
    max_run_duration: timedelta,
) -> bool:
    heartbeat_at = pipeline_run.heartbeat_at
    started_at = pipeline_run.started_at

    if heartbeat_at is not None and _age(now, heartbeat_at) > heartbeat_timeout:
        return True

    if started_at is not None and _age(now, started_at) > max_run_duration:
        return True

    return False


def _age(now: datetime, past: datetime) -> timedelta:
    if past.tzinfo is None:
        past = past.replace(tzinfo=UTC)
    return now - past


def _isoformat(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(UTC).isoformat()
