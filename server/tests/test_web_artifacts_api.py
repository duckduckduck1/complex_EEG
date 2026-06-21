"""Тесты Web API для скачивания pipeline artifacts."""

from __future__ import annotations

import shutil
from collections.abc import Iterator
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.api.deps_auth import require_current_user
from app.api.routes_web_artifacts import get_web_artifact_service
from app.db.models import Experiment, PipelineArtifact
from app.features.auth import CurrentUser
from app.features.web_artifacts import WebArtifactService
from app.main import app


ARTIFACT_ENDPOINT = (
    "/api/v1/web/experiments/exp_alpha/artifacts/01HY7M8M9RF2K0Z6GNZ6D7Q7AP"
)
PIPELINE_RUN_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"
ARTIFACT_ID = "01HY7M8M9RF2K0Z6GNZ6D7Q7AP"
TEST_USER = CurrentUser(
    id=UUID("00000000-0000-0000-0000-000000000001"),
    username="viewer_user",
    role="viewer",
)


class FakeWebArtifactRepository:
    """In-memory repository для artifact download tests."""

    def __init__(self) -> None:
        self.experiments = [
            Experiment(
                experiment_id="exp_alpha",
                display_name="Alpha experiment",
                status="processed",
            )
        ]
        self.artifacts = [
            PipelineArtifact(
                id=ARTIFACT_ID,
                pipeline_run_id=PIPELINE_RUN_ID,
                experiment_id="exp_alpha",
                name="summary.json",
                kind="summary",
                relative_path="artifacts/summary.json",
                media_type="application/json",
                size_bytes=18,
            )
        ]

    def experiment_exists(self, experiment_id: str) -> bool:
        return any(experiment.experiment_id == experiment_id for experiment in self.experiments)

    def get_artifact(self, experiment_id: str, artifact_id: str) -> PipelineArtifact | None:
        return next(
            (
                artifact
                for artifact in self.artifacts
                if artifact.experiment_id == experiment_id and artifact.id == artifact_id
            ),
            None,
        )


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


@pytest.fixture()
def artifact_client(workspace_tmp_path: Path) -> Iterator[TestClient]:
    """TestClient с fake artifact service и настоящим файлом artifact."""

    artifact_file = (
        workspace_tmp_path
        / "exp_alpha"
        / "runs"
        / PIPELINE_RUN_ID
        / "artifacts"
        / "summary.json"
    )
    artifact_file.parent.mkdir(parents=True, exist_ok=True)
    artifact_file.write_bytes(b'{"status": "ok"}\n')

    repository = FakeWebArtifactRepository()
    service = WebArtifactService(
        repository=repository,
        pipeline_results_root=workspace_tmp_path,
    )

    app.dependency_overrides[get_web_artifact_service] = lambda: service
    app.dependency_overrides[require_current_user] = lambda: TEST_USER
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


def test_download_artifact_requires_authentication() -> None:
    """Без web-auth cookie artifact download закрыт."""

    with TestClient(app) as client:
        response = client.get(ARTIFACT_ENDPOINT)

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "auth.required"


def test_download_artifact_returns_file(artifact_client: TestClient) -> None:
    """Endpoint отдаёт artifact по ID, а не по пользовательскому пути."""

    response = artifact_client.get(ARTIFACT_ENDPOINT)

    assert response.status_code == 200
    assert response.content == b'{"status": "ok"}\n'
    assert response.headers["content-type"].startswith("application/json")
    assert "summary.json" in response.headers["content-disposition"]


def test_download_artifact_returns_404_for_unknown_artifact(
    artifact_client: TestClient,
) -> None:
    """Неизвестный artifact_id возвращает стабильный 404."""

    response = artifact_client.get(
        "/api/v1/web/experiments/exp_alpha/artifacts/01HZ7M8M9RF2K0Z6GNZ6D7Q7AP"
    )

    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "artifact.not_found"


def test_download_artifact_returns_404_for_missing_file(
    workspace_tmp_path: Path,
) -> None:
    """Если запись в БД есть, но файла нет на диске, сервер не падает."""

    repository = FakeWebArtifactRepository()
    service = WebArtifactService(
        repository=repository,
        pipeline_results_root=workspace_tmp_path,
    )

    app.dependency_overrides[get_web_artifact_service] = lambda: service
    app.dependency_overrides[require_current_user] = lambda: TEST_USER
    with TestClient(app) as client:
        response = client.get(ARTIFACT_ENDPOINT)
    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "artifact.file_missing"


def test_download_artifact_rejects_unsafe_relative_path(
    workspace_tmp_path: Path,
) -> None:
    """Даже relative_path из БД не может выйти за пределы директории run."""

    outside_file = workspace_tmp_path / "outside.json"
    outside_file.write_text('{"secret": true}\n', encoding="utf-8")

    repository = FakeWebArtifactRepository()
    repository.artifacts[0].relative_path = "../../../outside.json"
    service = WebArtifactService(
        repository=repository,
        pipeline_results_root=workspace_tmp_path,
    )

    app.dependency_overrides[get_web_artifact_service] = lambda: service
    app.dependency_overrides[require_current_user] = lambda: TEST_USER
    with TestClient(app) as client:
        response = client.get(ARTIFACT_ENDPOINT)
    app.dependency_overrides.clear()

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "artifact.path_unsafe"
    assert b"secret" not in response.content
