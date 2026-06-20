"""Тесты Web API для списка и карточки экспериментов."""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.deps_auth import require_current_user
from app.api.routes_web_experiments import get_web_experiment_service
from app.db.models import (
    Experiment,
    ExperimentEvent,
    PipelineArtifact,
    PipelineRun,
    SourceFile,
)
from app.features.auth import CurrentUser
from app.features.web_experiments import (
    ExperimentListFilters,
    ExperimentSort,
    WebExperimentService,
)
from app.main import app


WEB_EXPERIMENTS_ENDPOINT = "/api/v1/web/experiments"
BASE_TIME = datetime(2026, 6, 21, 10, 0, tzinfo=UTC)
TEST_USER = CurrentUser(
    id=UUID("00000000-0000-0000-0000-000000000001"),
    username="lab_user",
    role="viewer",
)


class FakeWebExperimentRepository:
    """In-memory repository для HTTP-тестов Web UI endpoints."""

    def __init__(self) -> None:
        self.experiments = [
            Experiment(
                experiment_id="exp_alpha",
                display_name="Alpha experiment",
                status="processed",
                storage_bucket="complex-eeg-bronze",
                storage_prefix="eeg/exp_alpha/",
                source_path="/srv/complex_eeg/experiments/exp_alpha/source",
                validation_report_path="/srv/complex_eeg/experiments/exp_alpha/validation/report.json",
                metadata_json={"animal_id": "mouse_1"},
                uploaded_at=BASE_TIME,
                accepted_at=BASE_TIME + timedelta(minutes=5),
                updated_at=BASE_TIME + timedelta(minutes=20),
            ),
            Experiment(
                experiment_id="exp_beta",
                display_name="Beta experiment",
                status="validation_failed",
                validation_error_code="validation.signal_size_invalid",
                validation_error_message="signal.bin size must be divisible by 4",
                metadata_json={},
                uploaded_at=BASE_TIME - timedelta(days=1),
                accepted_at=None,
                updated_at=BASE_TIME - timedelta(days=1),
            ),
        ]
        self.latest_pipeline_status = {"exp_alpha": "succeeded"}
        self.source_files = [
            SourceFile(
                experiment_id="exp_alpha",
                name="signal.bin",
                relative_path="signal.bin",
                bucket="complex-eeg-bronze",
                object_key="eeg/exp_alpha/signal.bin",
                size_bytes=4000,
                sha256="a" * 64,
            ),
            SourceFile(
                experiment_id="exp_alpha",
                name="experiment.json",
                relative_path="experiment.json",
                bucket="complex-eeg-bronze",
                object_key="eeg/exp_alpha/experiment.json",
                size_bytes=512,
                sha256="b" * 64,
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
                started_at=BASE_TIME + timedelta(minutes=6),
                finished_at=BASE_TIME + timedelta(minutes=16),
                created_at=BASE_TIME + timedelta(minutes=6),
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
                created_at=BASE_TIME + timedelta(minutes=17),
            )
        ]
        self.events = [
            ExperimentEvent(
                experiment_id="exp_alpha",
                event_type="status_changed",
                from_status="validating",
                to_status="accepted",
                message="Experiment accepted",
                created_at=BASE_TIME + timedelta(minutes=5),
            )
        ]

    def count_experiments(self, filters: ExperimentListFilters) -> int:
        return len(self._filtered(filters))

    def list_experiments(self, filters: ExperimentListFilters) -> list[Experiment]:
        return self._sorted(self._filtered(filters), filters.sort)[
            filters.offset : filters.offset + filters.limit
        ]

    def get_experiment(self, experiment_id: str) -> Experiment | None:
        return next(
            (
                experiment
                for experiment in self.experiments
                if experiment.experiment_id == experiment_id
            ),
            None,
        )

    def get_latest_pipeline_status(self, experiment_id: str) -> str | None:
        return self.latest_pipeline_status.get(experiment_id)

    def list_source_files(self, experiment_id: str) -> list[SourceFile]:
        return [
            source_file
            for source_file in self.source_files
            if source_file.experiment_id == experiment_id
        ]

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

    def list_events(self, experiment_id: str) -> list[ExperimentEvent]:
        return [
            event
            for event in self.events
            if event.experiment_id == experiment_id
        ]

    def _filtered(self, filters: ExperimentListFilters) -> list[Experiment]:
        experiments = self.experiments

        if filters.status:
            experiments = [
                experiment
                for experiment in experiments
                if experiment.status == filters.status
            ]

        if filters.date_from is not None:
            experiments = [
                experiment
                for experiment in experiments
                if experiment.uploaded_at is not None
                and experiment.uploaded_at >= filters.date_from
            ]

        if filters.date_to is not None:
            experiments = [
                experiment
                for experiment in experiments
                if experiment.uploaded_at is not None
                and experiment.uploaded_at <= filters.date_to
            ]

        if filters.search:
            search = filters.search.casefold()
            experiments = [
                experiment
                for experiment in experiments
                if search in experiment.display_name.casefold()
                or search in experiment.experiment_id.casefold()
            ]

        return experiments

    @staticmethod
    def _sorted(experiments: list[Experiment], sort: ExperimentSort) -> list[Experiment]:
        if sort == "uploaded_at_asc":
            return sorted(experiments, key=lambda item: item.uploaded_at or datetime.min)
        if sort == "updated_at_desc":
            return sorted(experiments, key=lambda item: item.updated_at, reverse=True)
        if sort == "display_name_asc":
            return sorted(experiments, key=lambda item: item.display_name)
        if sort == "status_asc":
            return sorted(experiments, key=lambda item: item.status)
        return sorted(experiments, key=lambda item: item.uploaded_at or datetime.min, reverse=True)


@pytest.fixture()
def web_experiments_client() -> Iterator[TestClient]:
    """TestClient с fake service и авторизованным web-пользователем."""

    repository = FakeWebExperimentRepository()
    service = WebExperimentService(repository)

    app.dependency_overrides[get_web_experiment_service] = lambda: service
    app.dependency_overrides[require_current_user] = lambda: TEST_USER
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


def test_list_experiments_requires_authentication() -> None:
    """Список экспериментов закрыт web-auth сессией."""

    with TestClient(app) as client:
        response = client.get(WEB_EXPERIMENTS_ENDPOINT)

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "auth.required"


def test_list_experiments_returns_page(web_experiments_client: TestClient) -> None:
    """GET /web/experiments отдаёт страницу таблицы без внутренних путей."""

    response = web_experiments_client.get(WEB_EXPERIMENTS_ENDPOINT)

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert body["limit"] == 50
    assert body["offset"] == 0
    assert body["items"][0]["experiment_id"] == "exp_alpha"
    assert body["items"][0]["last_pipeline_status"] == "succeeded"
    assert "source_path" not in body["items"][0]
    assert "storage_bucket" not in body["items"][0]


def test_list_experiments_applies_filters(web_experiments_client: TestClient) -> None:
    """Фильтры status/search/date работают как контракт таблицы."""

    response = web_experiments_client.get(
        WEB_EXPERIMENTS_ENDPOINT,
        params={
            "status": "validation_failed",
            "search": "beta",
            "date_from": (BASE_TIME - timedelta(days=2)).isoformat(),
            "date_to": BASE_TIME.isoformat(),
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["experiment_id"] == "exp_beta"
    assert body["items"][0]["last_error"]["code"] == "validation.signal_size_invalid"


def test_list_experiments_rejects_invalid_date_range(
    web_experiments_client: TestClient,
) -> None:
    """date_from позже date_to возвращает стабильную query-ошибку."""

    response = web_experiments_client.get(
        WEB_EXPERIMENTS_ENDPOINT,
        params={
            "date_from": BASE_TIME.isoformat(),
            "date_to": (BASE_TIME - timedelta(days=1)).isoformat(),
        },
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "request.invalid_query"


def test_get_experiment_detail_returns_safe_card(
    web_experiments_client: TestClient,
) -> None:
    """Карточка эксперимента не раскрывает server filesystem paths и object keys."""

    response = web_experiments_client.get(f"{WEB_EXPERIMENTS_ENDPOINT}/exp_alpha")

    assert response.status_code == 200
    body = response.json()
    assert body["experiment_id"] == "exp_alpha"
    assert body["metadata"] == {"animal_id": "mouse_1"}
    assert body["validation"] == {"status": "accepted", "error": None}
    assert {file["name"] for file in body["source_files"]} == {
        "experiment.json",
        "signal.bin",
    }
    assert body["source_files"][0]["download_allowed"] is False
    assert body["pipeline_runs"][0]["artifacts"][0]["artifact_id"] == "01HY7M8M9RF2K0Z6GNZ6D7Q7AP"
    assert body["events"][0]["event_type"] == "status_changed"

    serialized = str(body)
    assert "/srv/complex_eeg" not in serialized
    assert "object_key" not in serialized
    assert "storage_bucket" not in serialized
    assert "complex-eeg-bronze" not in serialized


def test_get_experiment_detail_returns_404_for_unknown(
    web_experiments_client: TestClient,
) -> None:
    """Неизвестный experiment_id возвращает machine-readable 404."""

    response = web_experiments_client.get(f"{WEB_EXPERIMENTS_ENDPOINT}/missing")

    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "experiment.not_found"
