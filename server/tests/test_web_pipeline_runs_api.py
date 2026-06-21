"""Тесты Web API для pipeline runs."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.deps_auth import require_current_user
from app.api.routes_web_pipeline import get_web_pipeline_run_service
from app.core.config import settings
from app.db.models import AuditEvent, Experiment, ExperimentEvent, PipelineArtifact, PipelineRun
from app.features.auth import CurrentUser
from app.features.web_pipeline_runs import (
    ACTIVE_PIPELINE_RUN_STATUSES,
    WebPipelineRunService,
)
from app.main import app


WEB_PIPELINE_ENDPOINT = "/api/v1/web/experiments/exp_alpha/pipeline-runs"
BASE_TIME = datetime(2026, 6, 21, 11, 0, tzinfo=UTC)


@dataclass(frozen=True)
class WebPipelineTestContext:
    """Объекты, которые нужны тесту после HTTP-вызова."""

    client: TestClient
    repository: "FakeWebPipelineRunRepository"


class FakeWebPipelineRunRepository:
    """In-memory repository для тестов pipeline Web API."""

    def __init__(self) -> None:
        self.experiments = [
            Experiment(
                experiment_id="exp_alpha",
                display_name="Alpha experiment",
                status="processed",
                uploaded_at=BASE_TIME - timedelta(hours=1),
                accepted_at=BASE_TIME - timedelta(minutes=50),
            ),
            Experiment(
                experiment_id="exp_failed_validation",
                display_name="Failed validation",
                status="validation_failed",
                validation_error_code="validation.signal_size_invalid",
            ),
        ]
        self.pipeline_runs = [
            PipelineRun(
                id="01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
                experiment_id="exp_alpha",
                status="succeeded",
                trigger_type="auto_primary",
                pipeline_version="dev",
                result_path="/srv/complex_eeg/pipeline_results/exp_alpha/runs/01HX",
                started_at=BASE_TIME - timedelta(minutes=40),
                finished_at=BASE_TIME - timedelta(minutes=30),
                created_at=BASE_TIME - timedelta(minutes=40),
            )
        ]
        self.pipeline_artifacts = [
            PipelineArtifact(
                id="01HY7M8M9RF2K0Z6GNZ6D7Q7AP",
                pipeline_run_id="01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
                experiment_id="exp_alpha",
                name="summary.json",
                kind="summary",
                relative_path="artifacts/summary.json",
                media_type="application/json",
                size_bytes=1234,
                created_at=BASE_TIME - timedelta(minutes=29),
            )
        ]
        self.experiment_events: list[ExperimentEvent] = []
        self.audit_events: list[AuditEvent] = []
        self.commits = 0

    def get_experiment(self, experiment_id: str) -> Experiment | None:
        return next(
            (
                experiment
                for experiment in self.experiments
                if experiment.experiment_id == experiment_id
            ),
            None,
        )

    def list_pipeline_runs(self, experiment_id: str) -> list[PipelineRun]:
        return [
            pipeline_run
            for pipeline_run in self.pipeline_runs
            if pipeline_run.experiment_id == experiment_id
        ]

    def list_pipeline_artifacts(self, pipeline_run_id: str) -> list[PipelineArtifact]:
        return [
            artifact
            for artifact in self.pipeline_artifacts
            if artifact.pipeline_run_id == pipeline_run_id
        ]

    def has_active_pipeline_run(self, experiment_id: str) -> bool:
        return any(
            pipeline_run.experiment_id == experiment_id
            and pipeline_run.status in ACTIVE_PIPELINE_RUN_STATUSES
            for pipeline_run in self.pipeline_runs
        )

    def add_manual_repeat_run(
        self,
        *,
        experiment: Experiment,
        pipeline_run: PipelineRun,
        actor_user_id: UUID,
        actor_username: str,
        reason: str | None,
    ) -> None:
        self.pipeline_runs.append(pipeline_run)
        self.experiment_events.append(
            ExperimentEvent(
                experiment_id=experiment.experiment_id,
                event_type="pipeline_repeat_requested",
                from_status=experiment.status,
                to_status=experiment.status,
                message=reason,
                details={
                    "pipeline_run_id": pipeline_run.id,
                    "actor_username": actor_username,
                },
            )
        )
        self.audit_events.append(
            AuditEvent(
                actor_user_id=actor_user_id,
                event_type="pipeline.repeat_requested",
                experiment_id=experiment.experiment_id,
                pipeline_run_id=pipeline_run.id,
                details={"reason": reason},
            )
        )

    def commit(self) -> None:
        self.commits += 1


def _current_user(role: str) -> CurrentUser:
    return CurrentUser(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        username=f"{role}_user",
        role=role,
    )


@pytest.fixture()
def viewer_pipeline_client() -> Iterator[WebPipelineTestContext]:
    """TestClient с viewer-пользователем."""

    yield from _pipeline_client(role="viewer")


@pytest.fixture()
def operator_pipeline_client(monkeypatch: pytest.MonkeyPatch) -> Iterator[WebPipelineTestContext]:
    """TestClient с operator-пользователем."""

    monkeypatch.setattr(settings, "pipeline_version", "test-version")
    yield from _pipeline_client(role="operator")


def _pipeline_client(role: str) -> Iterator[WebPipelineTestContext]:
    repository = FakeWebPipelineRunRepository()
    service = WebPipelineRunService(repository)

    app.dependency_overrides[get_web_pipeline_run_service] = lambda: service
    app.dependency_overrides[require_current_user] = lambda: _current_user(role)
    with TestClient(app) as client:
        yield WebPipelineTestContext(client=client, repository=repository)
    app.dependency_overrides.clear()


def test_list_pipeline_runs_requires_authentication() -> None:
    """GET pipeline-runs закрыт web-auth сессией."""

    with TestClient(app) as client:
        response = client.get(WEB_PIPELINE_ENDPOINT)

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "auth.required"


def test_viewer_can_list_pipeline_runs(
    viewer_pipeline_client: WebPipelineTestContext,
) -> None:
    """viewer может смотреть историю pipeline runs."""

    response = viewer_pipeline_client.client.get(WEB_PIPELINE_ENDPOINT)

    assert response.status_code == 200
    body = response.json()
    assert body["items"][0]["pipeline_run_id"] == "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"
    assert body["items"][0]["status"] == "succeeded"
    assert body["items"][0]["artifacts"][0]["artifact_id"] == "01HY7M8M9RF2K0Z6GNZ6D7Q7AP"
    assert "/srv/complex_eeg" not in str(body)
    assert "result_path" not in str(body)


def test_list_pipeline_runs_returns_404_for_unknown_experiment(
    viewer_pipeline_client: WebPipelineTestContext,
) -> None:
    """Неизвестный experiment_id возвращает стабильный 404."""

    response = viewer_pipeline_client.client.get(
        "/api/v1/web/experiments/missing/pipeline-runs"
    )

    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "experiment.not_found"


def test_viewer_cannot_create_repeat_run(
    viewer_pipeline_client: WebPipelineTestContext,
) -> None:
    """viewer не имеет права ставить повторную обработку в очередь."""

    response = viewer_pipeline_client.client.post(
        WEB_PIPELINE_ENDPOINT,
        json={"reason": "check result"},
    )

    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "auth.forbidden"


def test_operator_can_create_repeat_run(
    operator_pipeline_client: WebPipelineTestContext,
) -> None:
    """operator создаёт queued manual_repeat run и audit/event записи."""

    response = operator_pipeline_client.client.post(
        WEB_PIPELINE_ENDPOINT,
        json={
            "reason": "manual quality check",
            "params": {"band": "delta"},
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "queued"
    assert body["trigger_type"] == "manual_repeat"
    assert body["pipeline_version"] == "test-version"
    assert len(body["pipeline_run_id"]) == 26
    assert body["artifacts"] == []

    repository = operator_pipeline_client.repository
    created_run = repository.pipeline_runs[-1]
    assert created_run.params_json == {"band": "delta"}
    assert repository.experiment_events[-1].event_type == "pipeline_repeat_requested"
    assert repository.audit_events[-1].event_type == "pipeline.repeat_requested"
    assert repository.commits == 1


def test_repeat_run_rejects_not_ready_experiment(
    operator_pipeline_client: WebPipelineTestContext,
) -> None:
    """validation_failed experiment нельзя повторно обрабатывать."""

    response = operator_pipeline_client.client.post(
        "/api/v1/web/experiments/exp_failed_validation/pipeline-runs",
        json={"reason": "not ready"},
    )

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "pipeline.experiment_not_ready"


def test_repeat_run_rejects_active_pipeline_run(
    operator_pipeline_client: WebPipelineTestContext,
) -> None:
    """Нельзя создать второй queued/running run для одного эксперимента."""

    operator_pipeline_client.repository.pipeline_runs.append(
        PipelineRun(
            id="01HZ7M8M9RF2K0Z6GNZ6D7Q7AP",
            experiment_id="exp_alpha",
            status="queued",
            trigger_type="manual_repeat",
            pipeline_version="dev",
        )
    )

    response = operator_pipeline_client.client.post(
        WEB_PIPELINE_ENDPOINT,
        json={"reason": "duplicate"},
    )

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "pipeline.active_run_exists"
