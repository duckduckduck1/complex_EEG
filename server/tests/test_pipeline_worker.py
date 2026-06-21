"""Тесты service-слоя pipeline worker без настоящей БД."""

from __future__ import annotations

import json
import shutil
from collections.abc import Callable, Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest

from app.db.models import Experiment, ExperimentEvent, PipelineRun
from app.features.pipeline_worker import (
    EXPERIMENT_STATUS_PROCESSED,
    EXPERIMENT_STATUS_PROCESSING,
    EXPERIMENT_STATUS_PROCESSING_FAILED,
    PIPELINE_STATUS_FAILED,
    PIPELINE_STATUS_QUEUED,
    PIPELINE_STATUS_RUNNING,
    PIPELINE_STATUS_SUCCEEDED,
    PIPELINE_STUCK_ERROR_CODE,
    PipelineExecutionResult,
    PipelineRunJob,
    PipelineWorkerService,
)


FIXED_NOW = datetime(2026, 6, 21, 12, 0, tzinfo=UTC)
PIPELINE_RUN_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"


class FakePipelineWorkerRepository:
    """In-memory repository для проверки worker use cases."""

    def __init__(self) -> None:
        self.experiments: dict[str, Experiment] = {}
        self.pipeline_runs: dict[str, PipelineRun] = {}
        self.events: list[ExperimentEvent] = []
        self.commits = 0

    def fail_stuck_runs(
        self,
        *,
        now: datetime,
        heartbeat_timeout: timedelta,
        max_run_duration: timedelta,
    ) -> int:
        failed_count = 0

        for pipeline_run in self.pipeline_runs.values():
            if pipeline_run.status != PIPELINE_STATUS_RUNNING:
                continue

            heartbeat_stuck = (
                pipeline_run.heartbeat_at is not None
                and now - pipeline_run.heartbeat_at > heartbeat_timeout
            )
            duration_stuck = (
                pipeline_run.started_at is not None
                and now - pipeline_run.started_at > max_run_duration
            )
            if not heartbeat_stuck and not duration_stuck:
                continue

            pipeline_run.status = PIPELINE_STATUS_FAILED
            pipeline_run.error_code = PIPELINE_STUCK_ERROR_CODE
            pipeline_run.finished_at = now
            self._set_experiment_status(
                pipeline_run.experiment_id,
                EXPERIMENT_STATUS_PROCESSING_FAILED,
                event_type="pipeline_failed",
            )
            failed_count += 1

        if failed_count:
            self.commits += 1

        return failed_count

    def claim_next_queued_run(self, *, now: datetime) -> PipelineRunJob | None:
        queued_runs = sorted(
            (
                pipeline_run
                for pipeline_run in self.pipeline_runs.values()
                if pipeline_run.status == PIPELINE_STATUS_QUEUED
            ),
            key=lambda pipeline_run: pipeline_run.created_at,
        )
        if not queued_runs:
            return None

        pipeline_run = queued_runs[0]
        pipeline_run.status = PIPELINE_STATUS_RUNNING
        pipeline_run.started_at = now
        pipeline_run.heartbeat_at = now
        self._set_experiment_status(
            pipeline_run.experiment_id,
            EXPERIMENT_STATUS_PROCESSING,
            event_type="pipeline_started",
        )
        self.commits += 1

        return PipelineRunJob(
            pipeline_run_id=pipeline_run.id,
            experiment_id=pipeline_run.experiment_id,
            trigger_type=pipeline_run.trigger_type,
            pipeline_version=pipeline_run.pipeline_version,
            params=pipeline_run.params_json or {},
            started_at=pipeline_run.started_at,
        )

    def update_heartbeat(self, pipeline_run_id: str, *, heartbeat_at: datetime) -> None:
        self.pipeline_runs[pipeline_run_id].heartbeat_at = heartbeat_at
        self.commits += 1

    def mark_succeeded(
        self,
        pipeline_run_id: str,
        *,
        result_path: Path,
        finished_at: datetime,
    ) -> None:
        pipeline_run = self.pipeline_runs[pipeline_run_id]
        pipeline_run.status = PIPELINE_STATUS_SUCCEEDED
        pipeline_run.result_path = str(result_path)
        pipeline_run.finished_at = finished_at
        pipeline_run.heartbeat_at = finished_at
        self._set_experiment_status(
            pipeline_run.experiment_id,
            EXPERIMENT_STATUS_PROCESSED,
            event_type="pipeline_succeeded",
        )
        self.commits += 1

    def mark_failed(
        self,
        pipeline_run_id: str,
        *,
        error_code: str,
        error_message: str,
        finished_at: datetime,
    ) -> None:
        pipeline_run = self.pipeline_runs[pipeline_run_id]
        pipeline_run.status = PIPELINE_STATUS_FAILED
        pipeline_run.error_code = error_code
        pipeline_run.error_message = error_message
        pipeline_run.finished_at = finished_at
        pipeline_run.heartbeat_at = finished_at
        self._set_experiment_status(
            pipeline_run.experiment_id,
            EXPERIMENT_STATUS_PROCESSING_FAILED,
            event_type="pipeline_failed",
        )
        self.commits += 1

    def _set_experiment_status(
        self,
        experiment_id: str,
        status: str,
        *,
        event_type: str,
    ) -> None:
        experiment = self.experiments[experiment_id]
        from_status = experiment.status
        experiment.status = status
        self.events.append(
            ExperimentEvent(
                experiment_id=experiment_id,
                event_type=event_type,
                from_status=from_status,
                to_status=status,
                message=event_type,
            )
        )


class FailingExecutor:
    """Executor, который имитирует падение обработки."""

    def execute(
        self,
        job: PipelineRunJob,
        *,
        result_dir: Path,
        heartbeat: Callable[[], None],
    ) -> PipelineExecutionResult:
        heartbeat()
        raise RuntimeError("synthetic pipeline failure")


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def _repository_with_run(*, run_status: str = PIPELINE_STATUS_QUEUED) -> FakePipelineWorkerRepository:
    repository = FakePipelineWorkerRepository()
    repository.experiments["exp_alpha"] = Experiment(
        experiment_id="exp_alpha",
        display_name="Alpha experiment",
        status="accepted",
    )
    repository.pipeline_runs[PIPELINE_RUN_ID] = PipelineRun(
        id=PIPELINE_RUN_ID,
        experiment_id="exp_alpha",
        status=run_status,
        trigger_type="manual_repeat",
        pipeline_version="dev",
        params_json={"source": "test"},
        created_at=FIXED_NOW - timedelta(minutes=1),
    )
    return repository


def _service(
    repository: FakePipelineWorkerRepository,
    workspace_tmp_path: Path,
    *,
    executor: object | None = None,
) -> PipelineWorkerService:
    return PipelineWorkerService(
        repository=repository,
        pipeline_results_root=workspace_tmp_path,
        stuck_heartbeat_minutes=15,
        max_run_duration_hours=6,
        executor=executor,
        now=FIXED_NOW,
    )


def test_run_once_processes_queued_run_and_writes_manifest(
    workspace_tmp_path: Path,
) -> None:
    """queued run проходит полный skeleton flow до succeeded."""

    repository = _repository_with_run()
    service = _service(repository, workspace_tmp_path)

    result = service.run_once()

    pipeline_run = repository.pipeline_runs[PIPELINE_RUN_ID]
    manifest_path = (
        workspace_tmp_path
        / "exp_alpha"
        / "runs"
        / PIPELINE_RUN_ID
        / "result_manifest.json"
    )

    assert result.claimed_run_id == PIPELINE_RUN_ID
    assert result.status == PIPELINE_STATUS_SUCCEEDED
    assert pipeline_run.status == PIPELINE_STATUS_SUCCEEDED
    assert pipeline_run.result_path == str(manifest_path.parent)
    assert repository.experiments["exp_alpha"].status == EXPERIMENT_STATUS_PROCESSED
    assert manifest_path.is_file()

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["pipeline_run_id"] == PIPELINE_RUN_ID
    assert manifest["experiment_id"] == "exp_alpha"
    assert manifest["params"] == {"source": "test"}
    assert manifest["artifacts"] == []
    assert {event.event_type for event in repository.events} == {
        "pipeline_started",
        "pipeline_succeeded",
    }


def test_run_once_returns_idle_when_queue_is_empty(workspace_tmp_path: Path) -> None:
    """Если queued задач нет, worker cycle завершается как idle."""

    repository = FakePipelineWorkerRepository()
    service = _service(repository, workspace_tmp_path)

    result = service.run_once()

    assert result.claimed_run_id is None
    assert result.status == "idle"
    assert result.stuck_failed_count == 0


def test_run_once_marks_run_failed_when_executor_raises(
    workspace_tmp_path: Path,
) -> None:
    """Ошибка executor'а переводит run и experiment в failed status."""

    repository = _repository_with_run()
    service = _service(repository, workspace_tmp_path, executor=FailingExecutor())

    result = service.run_once()

    pipeline_run = repository.pipeline_runs[PIPELINE_RUN_ID]
    assert result.status == PIPELINE_STATUS_FAILED
    assert result.message == "synthetic pipeline failure"
    assert pipeline_run.status == PIPELINE_STATUS_FAILED
    assert pipeline_run.error_code == "pipeline.skeleton_failed"
    assert repository.experiments["exp_alpha"].status == EXPERIMENT_STATUS_PROCESSING_FAILED


def test_run_once_fails_stuck_running_run_before_polling_queue(
    workspace_tmp_path: Path,
) -> None:
    """Watchdog часть worker cycle переводит старый running run в failed."""

    repository = _repository_with_run(run_status=PIPELINE_STATUS_RUNNING)
    stuck_run = repository.pipeline_runs[PIPELINE_RUN_ID]
    stuck_run.started_at = FIXED_NOW - timedelta(hours=7)
    stuck_run.heartbeat_at = FIXED_NOW - timedelta(minutes=20)
    repository.experiments["exp_alpha"].status = EXPERIMENT_STATUS_PROCESSING
    service = _service(repository, workspace_tmp_path)

    result = service.run_once()

    assert result.claimed_run_id is None
    assert result.status == "idle"
    assert result.stuck_failed_count == 1
    assert stuck_run.status == PIPELINE_STATUS_FAILED
    assert stuck_run.error_code == PIPELINE_STUCK_ERROR_CODE
    assert repository.experiments["exp_alpha"].status == EXPERIMENT_STATUS_PROCESSING_FAILED
