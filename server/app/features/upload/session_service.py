"""Service-слой upload sessions.

Этот модуль держит бизнес-правила создания, чтения и отмены upload session.
Он не зависит от FastAPI и почти не зависит от SQLAlchemy: наружу ему нужен
repository-объект с маленьким набором методов. Поэтому правила можно тестировать
без реальной PostgreSQL, а DB owner сможет менять внутренности репозитория без
переписывания API-логики.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import Experiment, UploadSession
from app.features.upload.staging import build_upload_session_dir
from app.features.validation.package_validator import EXPERIMENT_ID_PATTERN


CROCKFORD_BASE32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
REQUIRED_UPLOAD_FILES = ("signal.bin", "experiment.json")
OPTIONAL_UPLOAD_FILES = ("journal.ndjson", "app.log")
DEFAULT_UPLOAD_FILES = REQUIRED_UPLOAD_FILES + OPTIONAL_UPLOAD_FILES
ACTIVE_UPLOAD_SESSION_STATUSES = frozenset({"created", "uploading", "completed", "validating"})
FINAL_UPLOAD_SESSION_STATUSES = frozenset({"accepted", "failed", "expired", "cancelled"})


class UploadSessionServiceError(ValueError):
    """Базовая ошибка service-слоя upload sessions."""


class UploadSessionAlreadyExistsError(UploadSessionServiceError):
    """Для experiment_id уже есть accepted experiment или активная upload session."""


class UploadSessionNotFoundError(UploadSessionServiceError):
    """Upload session не найдена."""


class UploadSessionStateConflictError(UploadSessionServiceError):
    """Операция невозможна для текущего статуса upload session."""


@dataclass(frozen=True)
class UploadSessionView:
    """API-safe представление upload session без внутренних filesystem paths."""

    upload_session_id: str
    experiment_id: str
    status: str
    expected_files: list[str]
    uploaded_files: list[str]
    expires_at: datetime


class UploadSessionRepository(Protocol):
    """Минимальный контракт хранилища, который нужен service-слою."""

    def has_accepted_experiment(self, experiment_id: str) -> bool:
        """True, если experiment_id уже принят сервером."""

    def find_active_session_by_experiment_id(self, experiment_id: str) -> UploadSession | None:
        """Возвращает активную session для experiment_id, если она есть."""

    def get_by_id(self, upload_session_id: str) -> UploadSession | None:
        """Возвращает upload session по ULID."""

    def add(self, upload_session: UploadSession) -> None:
        """Добавляет новую upload session в unit of work."""

    def commit(self) -> None:
        """Фиксирует изменения."""


class SqlAlchemyUploadSessionRepository:
    """SQLAlchemy-реализация repository для PostgreSQL.

    Важно: здесь нет сложных транзакционных гарантий уникальности активной
    session. На первом шаге API получает рабочий слой. Финальную защиту от race
    conditions DB owner должен закрыть constraint'ами или transaction locking.
    """

    def __init__(self, db: Session) -> None:
        self._db = db

    def has_accepted_experiment(self, experiment_id: str) -> bool:
        statement = select(Experiment.id).where(
            Experiment.experiment_id == experiment_id,
            Experiment.status == "accepted",
        )
        return self._db.execute(statement).first() is not None

    def find_active_session_by_experiment_id(self, experiment_id: str) -> UploadSession | None:
        statement = select(UploadSession).where(
            UploadSession.experiment_id == experiment_id,
            UploadSession.status.in_(ACTIVE_UPLOAD_SESSION_STATUSES),
        )
        return self._db.execute(statement).scalars().first()

    def get_by_id(self, upload_session_id: str) -> UploadSession | None:
        return self._db.get(UploadSession, upload_session_id)

    def add(self, upload_session: UploadSession) -> None:
        self._db.add(upload_session)

    def commit(self) -> None:
        self._db.commit()


class UploadSessionService:
    """Use cases для upload session API."""

    def __init__(
        self,
        *,
        repository: UploadSessionRepository,
        upload_tmp_root: str | Path,
        ttl_hours: int,
        now: datetime | None = None,
    ) -> None:
        self._repository = repository
        self._upload_tmp_root = Path(upload_tmp_root)
        self._ttl_hours = ttl_hours
        self._now = now

    def create_session(
        self,
        *,
        experiment_id: str,
        expected_files: list[str] | None = None,
        client_id: str = "web_ui",
    ) -> UploadSessionView:
        """Создаёт upload session и временную директорию для будущих файлов."""

        self._validate_experiment_id(experiment_id)
        normalized_expected_files = _normalize_expected_files(expected_files)

        if self._repository.has_accepted_experiment(experiment_id):
            raise UploadSessionAlreadyExistsError("experiment_id is already accepted")

        active_session = self._repository.find_active_session_by_experiment_id(experiment_id)
        if active_session is not None:
            raise UploadSessionAlreadyExistsError(
                "active upload session already exists for experiment_id"
            )

        upload_session_id = generate_ulid(now=self._current_time())
        session_dir = build_upload_session_dir(self._upload_tmp_root, upload_session_id)
        session_dir.mkdir(parents=True, exist_ok=False)

        expires_at = self._current_time() + timedelta(hours=self._ttl_hours)
        upload_session = UploadSession(
            id=upload_session_id,
            experiment_id=experiment_id,
            status="uploading",
            tmp_path=str(session_dir),
            client_id=client_id,
            expected_files={"files": normalized_expected_files},
            uploaded_files={"files": []},
            expires_at=expires_at,
        )

        self._repository.add(upload_session)
        self._repository.commit()

        return _to_view(upload_session)

    def get_session(self, upload_session_id: str) -> UploadSessionView:
        """Возвращает текущий статус upload session."""

        upload_session = self._get_existing_session(upload_session_id)
        self._expire_if_needed(upload_session)
        return _to_view(upload_session)

    def cancel_session(self, upload_session_id: str) -> UploadSessionView:
        """Отменяет upload session, если её ещё можно отменить."""

        upload_session = self._get_existing_session(upload_session_id)
        self._expire_if_needed(upload_session)

        if upload_session.status == "cancelled":
            return _to_view(upload_session)

        if upload_session.status in FINAL_UPLOAD_SESSION_STATUSES:
            raise UploadSessionStateConflictError(
                f"upload session cannot be cancelled from status {upload_session.status}"
            )

        upload_session.status = "cancelled"
        self._repository.commit()

        return _to_view(upload_session)

    def _get_existing_session(self, upload_session_id: str) -> UploadSession:
        upload_session = self._repository.get_by_id(upload_session_id)
        if upload_session is None:
            raise UploadSessionNotFoundError("upload session was not found")
        return upload_session

    def _expire_if_needed(self, upload_session: UploadSession) -> None:
        """Лениво переводит активную session в expired после TTL."""

        if (
            upload_session.status in ACTIVE_UPLOAD_SESSION_STATUSES
            and upload_session.expires_at <= self._current_time()
        ):
            upload_session.status = "expired"
            self._repository.commit()

    def _current_time(self) -> datetime:
        return self._now or datetime.now(UTC)

    @staticmethod
    def _validate_experiment_id(experiment_id: str) -> None:
        if not EXPERIMENT_ID_PATTERN.fullmatch(experiment_id):
            raise UploadSessionServiceError("experiment_id has invalid format")


def generate_ulid(*, now: datetime | None = None) -> str:
    """Генерирует ULID без внешней зависимости.

    ULID = 48 бит timestamp в миллисекундах + 80 бит случайности, закодированные
    в Crockford Base32. Такой ID сортируется примерно по времени создания и
    хорошо подходит для upload_session_id.
    """

    current_time = now or datetime.now(UTC)
    timestamp_ms = int(current_time.timestamp() * 1000)
    randomness = int.from_bytes(secrets.token_bytes(10), byteorder="big")
    value = (timestamp_ms << 80) | randomness

    return "".join(
        CROCKFORD_BASE32[(value >> shift) & 0b11111]
        for shift in range(125, -1, -5)
    )


def _normalize_expected_files(expected_files: list[str] | None) -> list[str]:
    files = expected_files or list(DEFAULT_UPLOAD_FILES)
    normalized = sorted(set(files))

    missing_required = set(REQUIRED_UPLOAD_FILES) - set(normalized)
    if missing_required:
        missing = ", ".join(sorted(missing_required))
        raise UploadSessionServiceError(f"expected_files must include required files: {missing}")

    return normalized


def _to_view(upload_session: UploadSession) -> UploadSessionView:
    return UploadSessionView(
        upload_session_id=upload_session.id,
        experiment_id=upload_session.experiment_id,
        status=upload_session.status,
        expected_files=_files_from_json(upload_session.expected_files),
        uploaded_files=_files_from_json(upload_session.uploaded_files),
        expires_at=upload_session.expires_at,
    )


def _files_from_json(value: dict[str, object] | None) -> list[str]:
    if not value:
        return []

    raw_files = value.get("files", [])
    if not isinstance(raw_files, list):
        return []

    return sorted(file_name for file_name in raw_files if isinstance(file_name, str))
