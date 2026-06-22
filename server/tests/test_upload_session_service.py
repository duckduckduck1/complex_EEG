"""Тесты service-слоя upload sessions без реальной БД."""

from __future__ import annotations

import logging
import shutil
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest

from app.core.config import settings
from app.db.models import (
    Experiment,
    ExperimentEvent,
    PipelineRun,
    SourceFile,
    UploadSession,
    UploadOrphanObject,
    UploadStorageEvent,
)
from app.features.upload.bronze_storage import (
    BronzeStorageError,
    BronzeUploadResult,
    build_bronze_upload_result,
)
from app.features.upload.file_inventory import SourceFileInfo
from app.features.upload.promotion import UploadPromotionResult
from app.features.upload.session_service import (
    ACTIVE_UPLOAD_SESSION_STATUSES,
    PIPELINE_RUN_STATUS_QUEUED,
    PRIMARY_PIPELINE_TRIGGER_TYPE,
    SqlAlchemyUploadSessionRepository,
    UploadDatabaseCommitError,
    UploadLocalCleanupError,
    UploadObjectStorageUnavailableError,
    UploadSessionAlreadyExistsError,
    UploadSessionIncompleteError,
    UploadSessionNotFoundError,
    UploadSessionService,
    UploadSessionServiceError,
    UploadSessionStateConflictError,
    generate_ulid,
)
from app.features.validation.package_validator import ValidationResult
from app.features.upload.staging import UPLOAD_SESSION_ID_PATTERN


FIXED_NOW = datetime(2026, 6, 20, 12, 0, tzinfo=UTC)
VALID_UPLOAD_SESSION_ID = "01HX7M8M9RF2K0Z6GNZ6D7Q7AP"


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
        self.experiment_events: list[ExperimentEvent] = []
        self.pipeline_runs: list[PipelineRun] = []
        self.upload_sessions: dict[str, UploadSession] = {}
        self.source_files: list[SourceFile] = []
        self.upload_storage_events: list[UploadStorageEvent] = []
        self.upload_orphan_objects: list[UploadOrphanObject] = []
        self.locked_session_ids: list[str] = []
        self.commits = 0
        self.rollbacks = 0
        self.fail_next_commit = False
        self._last_accept_upload_session_id: str | None = None
        self._last_accept_experiment_id: str | None = None

    def has_registered_experiment(self, experiment_id: str) -> bool:
        return any(experiment.experiment_id == experiment_id for experiment in self.experiments)

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

    def get_by_id_for_update(self, upload_session_id: str) -> UploadSession | None:
        self.locked_session_ids.append(upload_session_id)
        return self.upload_sessions.get(upload_session_id)

    def add(self, upload_session: UploadSession) -> None:
        self.upload_sessions[upload_session.id] = upload_session

    def record_accepted_experiment(
        self,
        *,
        upload_session: UploadSession,
        promotion_result: UploadPromotionResult,
        bronze_upload_result: BronzeUploadResult,
        validation_result: ValidationResult,
        accepted_at: datetime,
    ) -> None:
        self._last_accept_upload_session_id = upload_session.id
        self._last_accept_experiment_id = promotion_result.experiment_id
        self.experiments.append(
            Experiment(
                experiment_id=promotion_result.experiment_id,
                display_name=promotion_result.experiment_id,
                status="accepted",
                storage_bucket=bronze_upload_result.bucket,
                storage_prefix=bronze_upload_result.storage_prefix,
                source_path=None,
                validation_report_path=str(promotion_result.validation_report_path),
                metadata_json=validation_result.metadata,
                uploaded_at=upload_session.created_at,
                accepted_at=accepted_at,
            )
        )
        self.source_files.extend(
            SourceFile(
                experiment_id=promotion_result.experiment_id,
                name=source_file.name,
                relative_path=source_file.relative_path,
                bucket=source_file.bucket,
                object_key=source_file.object_key,
                size_bytes=source_file.size_bytes,
                sha256=source_file.sha256,
            )
            for source_file in bronze_upload_result.source_files
        )
        self.upload_storage_events.extend(
            UploadStorageEvent(
                upload_session_id=upload_session.id,
                experiment_id=promotion_result.experiment_id,
                event_type="minio_object_uploaded",
                status="succeeded",
                bucket=source_file.bucket,
                storage_prefix=bronze_upload_result.storage_prefix,
                object_key=source_file.object_key,
                message="Source file uploaded and verified in MinIO bronze",
                details={
                    "relative_path": source_file.relative_path,
                    "size_bytes": source_file.size_bytes,
                    "sha256": source_file.sha256,
                },
            )
            for source_file in bronze_upload_result.source_files
        )
        primary_pipeline_run_id = generate_ulid(now=accepted_at)
        self.pipeline_runs.append(
            PipelineRun(
                id=primary_pipeline_run_id,
                experiment_id=promotion_result.experiment_id,
                status=PIPELINE_RUN_STATUS_QUEUED,
                trigger_type=PRIMARY_PIPELINE_TRIGGER_TYPE,
                pipeline_version=settings.pipeline_version,
                params_json={},
            )
        )
        self.experiment_events.append(
            ExperimentEvent(
                experiment_id=promotion_result.experiment_id,
                event_type="pipeline_primary_queued",
                from_status="accepted",
                to_status="accepted",
                message="Primary pipeline run queued after upload acceptance",
                details={
                    "pipeline_run_id": primary_pipeline_run_id,
                    "trigger_type": PRIMARY_PIPELINE_TRIGGER_TYPE,
                },
            )
        )
        self.upload_storage_events.append(
            UploadStorageEvent(
                upload_session_id=upload_session.id,
                experiment_id=promotion_result.experiment_id,
                event_type="source_package_accepted",
                status="succeeded",
                bucket=bronze_upload_result.bucket,
                storage_prefix=bronze_upload_result.storage_prefix,
                message="Accepted source package metadata committed to PostgreSQL",
                details={
                    "source_file_count": len(bronze_upload_result.source_files),
                    "validation_report_path": str(promotion_result.validation_report_path),
                },
            )
        )

    def record_orphan_objects(
        self,
        *,
        upload_session: UploadSession,
        bronze_upload_result: BronzeUploadResult,
        reason: str,
        details: dict[str, object],
    ) -> None:
        self.upload_orphan_objects.extend(
            UploadOrphanObject(
                upload_session_id=upload_session.id,
                experiment_id=upload_session.experiment_id,
                bucket=source_file.bucket,
                storage_prefix=bronze_upload_result.storage_prefix,
                object_key=source_file.object_key,
                relative_path=source_file.relative_path,
                size_bytes=source_file.size_bytes,
                sha256=source_file.sha256,
                reason=reason,
                details=details,
            )
            for source_file in bronze_upload_result.source_files
        )

    def refresh_upload_session(self, upload_session: UploadSession) -> None:
        stored_session = self.upload_sessions[upload_session.id]
        upload_session.status = stored_session.status
        upload_session.completed_at = stored_session.completed_at

    def commit(self) -> None:
        if self.fail_next_commit:
            self.fail_next_commit = False
            raise RuntimeError("commit failed")
        self.commits += 1

    def rollback(self) -> None:
        self.rollbacks += 1
        if self._last_accept_experiment_id is not None:
            experiment_id = self._last_accept_experiment_id
            self.experiments = [
                experiment
                for experiment in self.experiments
                if experiment.experiment_id != experiment_id
            ]
            self.source_files = [
                source_file
                for source_file in self.source_files
                if source_file.experiment_id != experiment_id
            ]
            self.pipeline_runs = [
                pipeline_run
                for pipeline_run in self.pipeline_runs
                if pipeline_run.experiment_id != experiment_id
            ]
            self.experiment_events = [
                event
                for event in self.experiment_events
                if event.experiment_id != experiment_id
            ]
            self.upload_storage_events = [
                event
                for event in self.upload_storage_events
                if event.experiment_id != experiment_id
            ]
        if self._last_accept_upload_session_id is not None:
            upload_session = self.upload_sessions[self._last_accept_upload_session_id]
            upload_session.status = "uploading"
            upload_session.completed_at = None
        self._last_accept_experiment_id = None
        self._last_accept_upload_session_id = None


class FakeSqlAlchemySession:
    """Минимальная fake session: собирает ORM-объекты, которые repository хочет записать."""

    def __init__(self) -> None:
        self.added: list[object] = []
        self.commits = 0
        self.rollbacks = 0

    def add(self, item: object) -> None:
        self.added.append(item)

    def commit(self) -> None:
        self.commits += 1

    def rollback(self) -> None:
        self.rollbacks += 1


class RecordingBronzeObjectStorage:
    """Запоминает факт upload в bronze storage без сетевого MinIO."""

    def __init__(self, *, bucket: str = "test-bronze") -> None:
        self.bucket = bucket
        self.calls: list[tuple[str, Path, tuple[SourceFileInfo, ...]]] = []

    def upload_source_package(
        self,
        *,
        experiment_id: str,
        source_dir: Path,
        source_files: tuple[SourceFileInfo, ...],
    ) -> BronzeUploadResult:
        self.calls.append((experiment_id, source_dir, source_files))
        return build_bronze_upload_result(
            experiment_id=experiment_id,
            bucket=self.bucket,
            source_files=source_files,
        )


class FailingBronzeObjectStorage:
    """Имитирует недоступный MinIO во время complete upload."""

    def upload_source_package(
        self,
        *,
        experiment_id: str,
        source_dir: Path,
        source_files: tuple[SourceFileInfo, ...],
    ) -> BronzeUploadResult:
        raise BronzeStorageError("minio is unavailable")


class PartiallyFailingBronzeObjectStorage:
    """Загружает часть объектов в MinIO, затем падает.

    Несёт уже загруженные объекты в `BronzeStorageError.uploaded`, как это делает
    production-адаптер при сбое на втором файле.
    """

    def __init__(self, *, bucket: str = "test-bronze") -> None:
        self.bucket = bucket

    def upload_source_package(
        self,
        *,
        experiment_id: str,
        source_dir: Path,
        source_files: tuple[SourceFileInfo, ...],
    ) -> BronzeUploadResult:
        full = build_bronze_upload_result(
            experiment_id=experiment_id,
            bucket=self.bucket,
            source_files=source_files,
        )
        partial = BronzeUploadResult(
            bucket=full.bucket,
            storage_prefix=full.storage_prefix,
            source_files=full.source_files[:1],
        )
        raise BronzeStorageError("second object upload failed", uploaded=partial)


def _service(
    repository: FakeUploadSessionRepository,
    upload_tmp_root: Path,
    *,
    bronze_storage: RecordingBronzeObjectStorage | FailingBronzeObjectStorage | None = None,
    now: datetime = FIXED_NOW,
) -> UploadSessionService:
    return UploadSessionService(
        repository=repository,
        upload_tmp_root=upload_tmp_root,
        experiments_root=upload_tmp_root / "experiments",
        ttl_hours=24,
        bronze_storage=bronze_storage,
        now=now,
    )


def _write_valid_uploaded_package(
    service: UploadSessionService,
    upload_session_id: str,
    *,
    experiment_id: str = "exp_01",
    signal_bytes: bytes = b"\x00\x00\x00\x00" * 1000,
) -> None:
    signal_target = service.prepare_file_upload(upload_session_id, "signal.bin")
    signal_target.part_path.write_bytes(signal_bytes)
    _finish_test_upload_file(signal_target.part_path, signal_target.final_path)
    service.record_uploaded_file(upload_session_id, "signal.bin")

    metadata_target = service.prepare_file_upload(upload_session_id, "experiment.json")
    metadata_target.part_path.write_text(
        (
            "{"
            f'"experiment_id": "{experiment_id}", '
            '"metadata": {"animal_id": "mouse_1"}, '
            '"segments": [{"segment_id": "seg_1", "start_sample": 0, "end_sample": 1000}], '
            '"labels": [], '
            '"fbm_events": []'
            "}"
        ),
        encoding="utf-8",
    )
    _finish_test_upload_file(metadata_target.part_path, metadata_target.final_path)
    service.record_uploaded_file(upload_session_id, "experiment.json")


def _finish_test_upload_file(part_path: Path, final_path: Path) -> None:
    try:
        part_path.replace(final_path)
    except PermissionError:
        shutil.copy2(part_path, final_path)
        try:
            part_path.unlink()
        except PermissionError:
            return


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


def test_create_session_rejects_existing_experiment_in_processing_status(
    workspace_tmp_path: Path,
) -> None:
    """После старта worker experiment_id всё равно остаётся занятым для новых загрузок."""

    repository = FakeUploadSessionRepository()
    repository.experiments.append(
        Experiment(
            experiment_id="exp_01",
            display_name="exp_01",
            status="processing",
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
    assert repository.locked_session_ids == []


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


def test_prepare_and_record_uploaded_file_updates_session(workspace_tmp_path: Path) -> None:
    """После успешной записи файл появляется в uploaded_files."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")

    target = service.prepare_file_upload(created.upload_session_id, "experiment.json")
    target.part_path.write_text("{}", encoding="utf-8")
    _finish_test_upload_file(target.part_path, target.final_path)
    result = service.record_uploaded_file(created.upload_session_id, "experiment.json")

    assert target.final_path == workspace_tmp_path / created.upload_session_id / "source" / "experiment.json"
    assert result.uploaded_files == ["experiment.json"]


def test_prepare_file_upload_rejects_unexpected_file(workspace_tmp_path: Path) -> None:
    """Сервер принимает только файлы из upload-контракта."""

    service = _service(FakeUploadSessionRepository(), workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")

    with pytest.raises(UploadSessionServiceError):
        service.prepare_file_upload(created.upload_session_id, "../evil.txt")


def test_complete_session_accepts_valid_uploaded_package(workspace_tmp_path: Path) -> None:
    """Complete валидирует пакет, переносит его в permanent storage и пишет accepted."""

    repository = FakeUploadSessionRepository()
    bronze_storage = RecordingBronzeObjectStorage()
    service = _service(repository, workspace_tmp_path, bronze_storage=bronze_storage)
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)

    result = service.complete_session(created.upload_session_id)

    permanent_source = workspace_tmp_path / "experiments" / "exp_01" / "source"
    assert result.status == "accepted"
    assert result.accepted is True
    assert repository.locked_session_ids == [created.upload_session_id]
    assert not permanent_source.exists()
    assert repository.upload_sessions[created.upload_session_id].status == "accepted"
    assert repository.experiments[0].experiment_id == "exp_01"
    assert repository.experiments[0].storage_bucket == "test-bronze"
    assert repository.experiments[0].storage_prefix == "eeg/exp_01/"
    assert repository.experiments[0].source_path is None
    assert len(repository.source_files) == 2
    assert {source_file.object_key for source_file in repository.source_files} == {
        "eeg/exp_01/experiment.json",
        "eeg/exp_01/signal.bin",
    }
    assert result.bronze_upload_result is not None
    assert result.bronze_upload_result.bucket == "test-bronze"
    assert len(bronze_storage.calls) == 1
    assert bronze_storage.calls[0][0] == "exp_01"
    assert len(repository.pipeline_runs) == 1
    assert repository.pipeline_runs[0].experiment_id == "exp_01"
    assert repository.pipeline_runs[0].status == PIPELINE_RUN_STATUS_QUEUED
    assert repository.pipeline_runs[0].trigger_type == PRIMARY_PIPELINE_TRIGGER_TYPE
    assert repository.pipeline_runs[0].pipeline_version == settings.pipeline_version
    assert repository.experiment_events[0].event_type == "pipeline_primary_queued"
    assert {event.event_type for event in repository.upload_storage_events} == {
        "minio_object_uploaded",
        "source_package_accepted",
    }


def test_sqlalchemy_repository_records_primary_pipeline_run() -> None:
    """Реальный repository создаёт primary run в одной unit-of-work с accepted experiment."""

    fake_db = FakeSqlAlchemySession()
    repository = SqlAlchemyUploadSessionRepository(fake_db)  # type: ignore[arg-type]
    accepted_at = FIXED_NOW

    repository.record_accepted_experiment(
        upload_session=UploadSession(
            id=VALID_UPLOAD_SESSION_ID,
            experiment_id="exp_01",
            status="accepted",
            tmp_path="upload_tmp/session",
            client_id="web_ui",
            expected_files={"files": ["signal.bin", "experiment.json"]},
            uploaded_files={"files": ["signal.bin", "experiment.json"]},
            created_at=FIXED_NOW,
            completed_at=accepted_at,
            expires_at=FIXED_NOW + timedelta(hours=24),
        ),
        promotion_result=UploadPromotionResult(
            experiment_id="exp_01",
            experiment_dir=Path("experiments/exp_01"),
            source_dir=Path("experiments/exp_01/source"),
            validation_dir=Path("experiments/exp_01/validation"),
            validation_report_path=Path("experiments/exp_01/validation/validation_report.json"),
            source_files=(
                SourceFileInfo(
                    name="signal.bin",
                    relative_path="signal.bin",
                    size_bytes=4000,
                    sha256="0" * 64,
                ),
            ),
        ),
        bronze_upload_result=build_bronze_upload_result(
            experiment_id="exp_01",
            bucket="test-bronze",
            source_files=(
                SourceFileInfo(
                    name="signal.bin",
                    relative_path="signal.bin",
                    size_bytes=4000,
                    sha256="0" * 64,
                ),
            ),
        ),
        validation_result=ValidationResult(
            status="accepted",
            experiment_id="exp_01",
            metadata={"animal_id": "mouse_1"},
            signal_size_bytes=4000,
            sample_count=1000,
            errors=[],
        ),
        accepted_at=accepted_at,
    )

    pipeline_runs = [item for item in fake_db.added if isinstance(item, PipelineRun)]
    events = [item for item in fake_db.added if isinstance(item, ExperimentEvent)]
    experiments = [item for item in fake_db.added if isinstance(item, Experiment)]
    source_files = [item for item in fake_db.added if isinstance(item, SourceFile)]
    storage_events = [item for item in fake_db.added if isinstance(item, UploadStorageEvent)]

    assert experiments[0].storage_bucket == "test-bronze"
    assert experiments[0].storage_prefix == "eeg/exp_01/"
    assert experiments[0].source_path is None
    assert source_files[0].object_key == "eeg/exp_01/signal.bin"
    assert {event.event_type for event in storage_events} == {
        "minio_object_uploaded",
        "source_package_accepted",
    }
    assert len(pipeline_runs) == 1
    assert pipeline_runs[0].experiment_id == "exp_01"
    assert pipeline_runs[0].status == PIPELINE_RUN_STATUS_QUEUED
    assert pipeline_runs[0].trigger_type == PRIMARY_PIPELINE_TRIGGER_TYPE
    assert pipeline_runs[0].pipeline_version == settings.pipeline_version
    assert events[0].event_type == "pipeline_primary_queued"


def test_complete_session_writes_failed_report_for_invalid_package(
    workspace_tmp_path: Path,
) -> None:
    """Невалидный пакет остаётся в upload_tmp и получает validation report."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(
        service,
        created.upload_session_id,
        signal_bytes=b"\x00\x01",
    )

    result = service.complete_session(created.upload_session_id)

    report_path = workspace_tmp_path / created.upload_session_id / "validation_report.json"
    assert result.status == "failed"
    assert result.accepted is False
    assert report_path.is_file()
    assert repository.upload_sessions[created.upload_session_id].status == "failed"
    assert repository.experiments == []


def test_complete_session_does_not_accept_when_bronze_storage_fails(
    workspace_tmp_path: Path,
) -> None:
    """Если MinIO недоступен, accepted experiment и pipeline run не создаются."""

    repository = FakeUploadSessionRepository()
    service = _service(
        repository,
        workspace_tmp_path,
        bronze_storage=FailingBronzeObjectStorage(),
    )
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)

    with pytest.raises(UploadObjectStorageUnavailableError):
        service.complete_session(created.upload_session_id)

    assert not (workspace_tmp_path / "experiments" / "exp_01").exists()
    assert (workspace_tmp_path / created.upload_session_id / "source" / "signal.bin").is_file()
    assert repository.upload_sessions[created.upload_session_id].status == "uploading"
    assert repository.experiments == []
    assert repository.source_files == []
    assert repository.pipeline_runs == []


def test_complete_session_can_retry_after_bronze_storage_failure(
    workspace_tmp_path: Path,
) -> None:
    """MinIO failure не должен оставлять local promotion, который ломает retry."""

    repository = FakeUploadSessionRepository()
    service = _service(
        repository,
        workspace_tmp_path,
        bronze_storage=FailingBronzeObjectStorage(),
    )
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)

    with pytest.raises(UploadObjectStorageUnavailableError):
        service.complete_session(created.upload_session_id)

    retry_storage = RecordingBronzeObjectStorage()
    service._bronze_storage = retry_storage
    result = service.complete_session(created.upload_session_id)

    assert result.status == "accepted"
    assert len(retry_storage.calls) == 1
    assert repository.experiments[0].experiment_id == "exp_01"


def test_complete_session_keeps_local_source_copy_when_db_commit_fails(
    workspace_tmp_path: Path,
) -> None:
    """Если PostgreSQL commit падает после MinIO upload, local source остаётся для разбора."""

    repository = FakeUploadSessionRepository()
    bronze_storage = RecordingBronzeObjectStorage()
    service = _service(repository, workspace_tmp_path, bronze_storage=bronze_storage)
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)
    repository.fail_next_commit = True

    with pytest.raises(UploadDatabaseCommitError):
        service.complete_session(created.upload_session_id)

    permanent_source = workspace_tmp_path / "experiments" / "exp_01" / "source"
    assert permanent_source.exists()
    assert (permanent_source / "signal.bin").is_file()
    assert repository.rollbacks == 1
    assert len(bronze_storage.calls) == 1
    assert repository.upload_sessions[created.upload_session_id].status == "uploading"
    assert repository.experiments == []
    assert repository.pipeline_runs == []
    assert {item.object_key for item in repository.upload_orphan_objects} == {
        "eeg/exp_01/experiment.json",
        "eeg/exp_01/signal.bin",
    }


def test_complete_session_can_retry_after_db_commit_failure(
    workspace_tmp_path: Path,
) -> None:
    """Retry после failed DB commit удаляет old local promotion и принимает пакет заново."""

    repository = FakeUploadSessionRepository()
    bronze_storage = RecordingBronzeObjectStorage()
    service = _service(repository, workspace_tmp_path, bronze_storage=bronze_storage)
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)
    repository.fail_next_commit = True

    with pytest.raises(UploadDatabaseCommitError):
        service.complete_session(created.upload_session_id)

    result = service.complete_session(created.upload_session_id)

    assert result.status == "accepted"
    assert len(bronze_storage.calls) == 2
    assert len(repository.experiments) == 1
    assert repository.upload_sessions[created.upload_session_id].status == "accepted"


def test_complete_session_accepts_even_when_local_cleanup_fails(
    workspace_tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Сбой удаления локальной копии после commit не должен ломать accepted-ответ."""

    repository = FakeUploadSessionRepository()
    bronze_storage = RecordingBronzeObjectStorage()
    service = _service(repository, workspace_tmp_path, bronze_storage=bronze_storage)
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)

    monkeypatch.setattr(
        "app.features.upload.session_service._remove_permanent_source_dir",
        lambda source_dir: False,
    )

    with caplog.at_level(logging.WARNING):
        result = service.complete_session(created.upload_session_id)

    assert result.status == "accepted"
    assert result.accepted is True
    assert repository.experiments[0].experiment_id == "exp_01"
    assert len(repository.pipeline_runs) == 1
    # Локальную копию намеренно оставили (cleanup "не смог"), но приёмка прошла.
    permanent_source = workspace_tmp_path / "experiments" / "exp_01" / "source"
    assert permanent_source.exists()
    assert any(
        "failed to remove local source copy" in message for message in caplog.messages
    )


def test_complete_session_surfaces_clear_error_when_stale_dir_cannot_be_removed(
    workspace_tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Неудаляемый остаток промо-папки даёт понятную ошибку, а не promotion-конфликт."""

    repository = FakeUploadSessionRepository()
    service = _service(
        repository,
        workspace_tmp_path,
        bronze_storage=RecordingBronzeObjectStorage(),
    )
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)

    stale_dir = workspace_tmp_path / "experiments" / "exp_01"
    (stale_dir / "source").mkdir(parents=True)

    def _raise_oserror(path: object, *args: object, **kwargs: object) -> None:
        raise OSError("directory is locked")

    monkeypatch.setattr(
        "app.features.upload.session_service.shutil.rmtree", _raise_oserror
    )

    with pytest.raises(UploadLocalCleanupError):
        service.complete_session(created.upload_session_id)

    assert repository.experiments == []
    assert repository.upload_sessions[created.upload_session_id].status == "uploading"


def test_complete_session_records_orphans_for_partial_bronze_upload(
    workspace_tmp_path: Path,
) -> None:
    """Частично загруженные в MinIO объекты учитываются как orphan для cleanup."""

    repository = FakeUploadSessionRepository()
    service = _service(
        repository,
        workspace_tmp_path,
        bronze_storage=PartiallyFailingBronzeObjectStorage(),
    )
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)

    with pytest.raises(UploadObjectStorageUnavailableError):
        service.complete_session(created.upload_session_id)

    # Accepted не записан, local promotion удалён, но "висящий" объект зафиксирован.
    assert not (workspace_tmp_path / "experiments" / "exp_01").exists()
    assert repository.experiments == []
    assert repository.pipeline_runs == []
    assert len(repository.upload_orphan_objects) == 1
    orphan = repository.upload_orphan_objects[0]
    assert orphan.reason == "bronze_upload_partial_failure"
    assert orphan.object_key in {
        "eeg/exp_01/experiment.json",
        "eeg/exp_01/signal.bin",
    }
    assert repository.upload_sessions[created.upload_session_id].status == "uploading"


def test_complete_session_rejects_missing_required_files(workspace_tmp_path: Path) -> None:
    """Complete без обязательного файла возвращает service-level incomplete."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")
    target = service.prepare_file_upload(created.upload_session_id, "experiment.json")
    target.part_path.write_text("{}", encoding="utf-8")
    _finish_test_upload_file(target.part_path, target.final_path)
    service.record_uploaded_file(created.upload_session_id, "experiment.json")

    with pytest.raises(UploadSessionIncompleteError):
        service.complete_session(created.upload_session_id)


def test_complete_session_is_idempotent_for_accepted(workspace_tmp_path: Path) -> None:
    """Повторный complete для accepted session не запускает promotion второй раз."""

    repository = FakeUploadSessionRepository()
    service = _service(repository, workspace_tmp_path)
    created = service.create_session(experiment_id="exp_01")
    _write_valid_uploaded_package(service, created.upload_session_id)
    first_result = service.complete_session(created.upload_session_id)

    second_result = service.complete_session(created.upload_session_id)

    assert first_result.status == "accepted"
    assert second_result.status == "accepted"
    assert second_result.validation_result is None
    assert len(repository.experiments) == 1
    assert len(repository.pipeline_runs) == 1
