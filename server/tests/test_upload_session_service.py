"""Тесты service-слоя upload sessions без реальной БД."""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest

from app.db.models import Experiment, UploadSession
from app.features.upload.session_service import (
    ACTIVE_UPLOAD_SESSION_STATUSES,
    UploadSessionAlreadyExistsError,
    UploadSessionNotFoundError,
    UploadSessionService,
    UploadSessionServiceError,
    UploadSessionStateConflictError,
    generate_ulid,
)
from app.features.upload.staging import UPLOAD_SESSION_ID_PATTERN


FIXED_NOW = datetime(2026, 6, 20, 12, 0, tzinfo=UTC)


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт тестовую директорию внутри репозитория.

    Не используем стандартный pytest tmp_path: в Codex/Windows окружении он
    может попасть в системный Temp без прав на чтение.
    """

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    yield root


class FakeUploadSessionRepository:
    """In-memory repository для unit-тестов service-слоя."""

    def __init__(self) -> None:
        self.experiments: list[Experiment] = []
        self.upload_sessions: dict[str, UploadSession] = {}
        self.commits = 0

    def has_accepted_experiment(self, experiment_id: str) -> bool:
        return any(
            experiment.experiment_id == experiment_id and experiment.status == "accepted"
            for experiment in self.experiments
        )

    def find_active_session_by_experiment_id(self, experiment_id: str) -> UploadSession | None:
        for upload_session in self.upload_sessions.values():
            if (
                upload_session.experiment_id == experiment_id
                and upload_session.status in ACTIVE_UPLOAD_SESSION_STATUSES
            ):
                return upload_session
        return None

    def get_by_id(self, upload_session_id: str) -> UploadSession | None:
        return self.upload_sessions.get(upload_session_id)

    def add(self, upload_session: UploadSession) -> None:
        self.upload_sessions[upload_session.id] = upload_session

    def commit(self) -> None:
        self.commits += 1


def _service(
    repository: FakeUploadSessionRepository,
    upload_tmp_root: Path,
    *,
    now: datetime = FIXED_NOW,
) -> UploadSessionService:
    return UploadSessionService(
        repository=repository,
        upload_tmp_root=upload_tmp_root,
        ttl_hours=24,
        now=now,
    )


def test_generate_ulid_returns_valid_upload_session_id() -> None:
    """ULID должен подходить под тот же формат, который принимает staging layer."""

    upload_session_id = generate_ulid(now=FIXED_NOW)

    assert UPLOAD_SESSION_ID_PATTERN.fullmatch(upload_session_id)


def test_create_session_persists_upload_session_and_creates_tmp_dir(
    workspace_tmp_path: Path,
) -> None:
    """Создание session пишет запись в repository и создаёт временную директорию."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)

    result = service.create_session(experiment_id="exp_01")

    stored_session = repository.upload_sessions[result.upload_session_id]
    assert result.experiment_id == "exp_01"
    assert result.status == "uploading"
    assert result.expected_files == ["app.log", "experiment.json", "journal.ndjson", "signal.bin"]
    assert result.uploaded_files == []
    assert result.expires_at == FIXED_NOW + timedelta(hours=24)
    assert Path(stored_session.tmp_path).is_dir()
    assert repository.commits == 1


def test_create_session_rejects_invalid_experiment_id(workspace_tmp_path: Path) -> None:
    """Path traversal нельзя пропускать уже на этапе создания session."""

    service = _service(FakeUploadSessionRepository(), workspace_tmp_path)

    with pytest.raises(UploadSessionServiceError):
        service.create_session(experiment_id="../bad")


def test_create_session_rejects_missing_required_expected_file(
    workspace_tmp_path: Path,
) -> None:
    """expected_files не может исключить обязательный signal.bin или experiment.json."""

    service = _service(FakeUploadSessionRepository(), workspace_tmp_path)

    with pytest.raises(UploadSessionServiceError):
        service.create_session(
            experiment_id="exp_01",
            expected_files=["experiment.json"],
        )


def test_create_session_rejects_already_accepted_experiment(
    workspace_tmp_path: Path,
) -> None:
    """Принятый experiment_id нельзя загрузить повторно."""

    repository = FakeUploadSessionRepository()
    repository.experiments.append(
        Experiment(
            experiment_id="exp_01",
            display_name="exp_01",
            status="accepted",
        )
    )

    service = _service(repository, workspace_tmp_path)

    with pytest.raises(UploadSessionAlreadyExistsError):
        service.create_session(experiment_id="exp_01")


def test_create_session_rejects_active_session_for_same_experiment(
    workspace_tmp_path: Path,
) -> None:
    """Активная session блокирует вторую параллельную загрузку того же experiment_id."""

    repository = FakeUploadSessionRepository()
    repository.upload_sessions["01HX7M8M9RF2K0Z6GNZ6D7Q7AP"] = UploadSession(
        id="01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
        experiment_id="exp_01",
        status="uploading",
        tmp_path=str(workspace_tmp_path / "existing"),
        client_id="web_ui",
        expected_files={"files": ["signal.bin", "experiment.json"]},
        uploaded_files={"files": []},
        expires_at=FIXED_NOW + timedelta(hours=24),
    )

    service = _service(repository, workspace_tmp_path)

    with pytest.raises(UploadSessionAlreadyExistsError):
        service.create_session(experiment_id="exp_01")


def test_get_session_returns_status_view(workspace_tmp_path: Path) -> None:
    """Status check отдаёт публичную модель без tmp_path."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")

    result = service.get_session(created.upload_session_id)

    assert result.upload_session_id == created.upload_session_id
    assert result.status == "uploading"
    assert result.expected_files == created.expected_files


def test_get_session_expires_active_session_after_ttl(workspace_tmp_path: Path) -> None:
    """Просроченная active session лениво переводится в expired."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")
    expired_service = _service(
        repository,
        workspace_tmp_path,
        now=FIXED_NOW + timedelta(hours=25),
    )

    result = expired_service.get_session(created.upload_session_id)

    assert result.status == "expired"
    assert repository.upload_sessions[created.upload_session_id].status == "expired"


def test_get_session_raises_for_unknown_session(workspace_tmp_path: Path) -> None:
    """Неизвестный ULID возвращает service-level not found."""

    service = _service(FakeUploadSessionRepository(), workspace_tmp_path)

    with pytest.raises(UploadSessionNotFoundError):
        service.get_session("01HX7M8M9RF2K0Z6GNZ6D7Q7AP")


def test_cancel_session_sets_cancelled(workspace_tmp_path: Path) -> None:
    """Пользовательская отмена переводит active session в cancelled."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")

    result = service.cancel_session(created.upload_session_id)

    assert result.status == "cancelled"
    assert repository.upload_sessions[created.upload_session_id].status == "cancelled"


def test_cancel_session_is_idempotent_for_cancelled(workspace_tmp_path: Path) -> None:
    """Повторная отмена уже cancelled session возвращает текущий статус."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")
    service.cancel_session(created.upload_session_id)

    result = service.cancel_session(created.upload_session_id)

    assert result.status == "cancelled"


def test_cancel_session_rejects_final_status(workspace_tmp_path: Path) -> None:
    """Final statuses нельзя отменять повторно, кроме already-cancelled."""

    repository = FakeUploadSessionRepository()
    repository.upload_sessions["01HX7M8M9RF2K0Z6GNZ6D7Q7AP"] = UploadSession(
        id="01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
        experiment_id="exp_01",
        status="accepted",
        tmp_path=str(workspace_tmp_path / "existing"),
        client_id="web_ui",
        expected_files={"files": ["signal.bin", "experiment.json"]},
        uploaded_files={"files": []},
        expires_at=FIXED_NOW + timedelta(hours=24),
    )
    service = _service(repository, workspace_tmp_path)

    with pytest.raises(UploadSessionStateConflictError):
        service.cancel_session("01HX7M8M9RF2K0Z6GNZ6D7Q7AP")
