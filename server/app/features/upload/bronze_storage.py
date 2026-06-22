"""Upload accepted EEG source package into MinIO bronze storage.

Этот модуль держит работу с object storage отдельно от upload service. Так
бизнес-логика знает только контракт `BronzeObjectStorage`, а конкретный клиент
MinIO можно заменить в тестах или при будущей миграции на другой S3-compatible
backend.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Protocol
from urllib.parse import urlparse

from app.core.config import Settings
from app.features.upload.file_inventory import SourceFileInfo
from app.features.validation.package_validator import EXPERIMENT_ID_PATTERN


DEFAULT_STORAGE_PREFIX_ROOT = "eeg"


class BronzeStorageError(RuntimeError):
    """Object storage не смог сохранить accepted source package.

    При частичном сбое часть объектов уже могла попасть в bucket. Атрибут
    `uploaded` несёт уже загруженные объекты, чтобы upload flow мог записать их
    как orphan для последующего cleanup и не оставлять "висящие" объекты в MinIO.
    """

    def __init__(self, message: str, *, uploaded: "BronzeUploadResult | None" = None) -> None:
        super().__init__(message)
        self.uploaded = uploaded


@dataclass(frozen=True)
class BronzeStoredSourceFile:
    """Source-файл после загрузки в bronze bucket."""

    name: str
    relative_path: str
    bucket: str
    object_key: str
    size_bytes: int
    sha256: str


@dataclass(frozen=True)
class BronzeUploadResult:
    """Итог загрузки source package в bronze object storage."""

    bucket: str
    storage_prefix: str
    source_files: tuple[BronzeStoredSourceFile, ...]


class BronzeObjectStorage(Protocol):
    """Минимальный контракт object storage, который нужен upload flow."""

    def upload_source_package(
        self,
        *,
        experiment_id: str,
        source_dir: Path,
        source_files: tuple[SourceFileInfo, ...],
    ) -> BronzeUploadResult:
        """Загружает source-файлы accepted experiment в bronze bucket."""


class NoopBronzeObjectStorage:
    """Тестовая/local заглушка, которая строит bronze-ссылки без сетевого upload."""

    def __init__(
        self,
        *,
        bucket: str,
        prefix_root: str = DEFAULT_STORAGE_PREFIX_ROOT,
    ) -> None:
        self._bucket = bucket
        self._prefix_root = prefix_root

    def upload_source_package(
        self,
        *,
        experiment_id: str,
        source_dir: Path,
        source_files: tuple[SourceFileInfo, ...],
    ) -> BronzeUploadResult:
        _ensure_source_files_exist(source_dir=source_dir, source_files=source_files)
        return build_bronze_upload_result(
            experiment_id=experiment_id,
            bucket=self._bucket,
            source_files=source_files,
            prefix_root=self._prefix_root,
        )


class MinioBronzeObjectStorage:
    """MinIO реализация bronze object storage.

    Клиент MinIO импортируется лениво в `from_settings`, чтобы unit-тесты могли
    работать без установленного SDK. В Docker/VM пакет ставится через pyproject.
    """

    def __init__(
        self,
        *,
        client: object,
        bucket: str,
        prefix_root: str = DEFAULT_STORAGE_PREFIX_ROOT,
    ) -> None:
        self._client = client
        self._bucket = bucket
        self._prefix_root = prefix_root

    @classmethod
    def from_settings(cls, settings: Settings) -> "MinioBronzeObjectStorage":
        try:
            from minio import Minio
        except ImportError as exc:
            raise BronzeStorageError(
                "MinIO Python SDK is not installed; run `pip install -e .` for the server package"
            ) from exc

        endpoint, secure = parse_minio_endpoint(settings.minio_endpoint)
        client = Minio(
            endpoint,
            access_key=settings.minio_root_user,
            secret_key=settings.minio_root_password.get_secret_value(),
            secure=secure,
        )
        return cls(client=client, bucket=settings.minio_bucket_bronze)

    def upload_source_package(
        self,
        *,
        experiment_id: str,
        source_dir: Path,
        source_files: tuple[SourceFileInfo, ...],
    ) -> BronzeUploadResult:
        result = build_bronze_upload_result(
            experiment_id=experiment_id,
            bucket=self._bucket,
            source_files=source_files,
            prefix_root=self._prefix_root,
        )

        # Накапливаем уже загруженные объекты: если upload или последующая
        # проверка упадёт, эти объекты остаются в bucket и должны уехать в
        # orphan-учёт, а не "потеряться" в MinIO.
        uploaded: list[BronzeStoredSourceFile] = []

        for source_file in result.source_files:
            file_path = source_dir / source_file.relative_path
            if not file_path.is_file():
                raise BronzeStorageError(
                    f"source file is missing before bronze upload: {file_path}",
                    uploaded=_partial_bronze_result(result, uploaded),
                )

            try:
                self._client.fput_object(
                    bucket_name=source_file.bucket,
                    object_name=source_file.object_key,
                    file_path=str(file_path),
                    content_type=guess_content_type(source_file.relative_path),
                )
            except Exception as exc:
                raise BronzeStorageError(
                    f"failed to upload {source_file.relative_path} to bronze object storage",
                    uploaded=_partial_bronze_result(result, uploaded),
                ) from exc

            uploaded.append(source_file)

        for source_file in result.source_files:
            try:
                self._client.stat_object(
                    bucket_name=source_file.bucket,
                    object_name=source_file.object_key,
                )
            except Exception as exc:
                raise BronzeStorageError(
                    f"uploaded object is not readable in bronze object storage: {source_file.relative_path}",
                    uploaded=_partial_bronze_result(result, uploaded),
                ) from exc

        return result


def build_bronze_upload_result(
    *,
    experiment_id: str,
    bucket: str,
    source_files: tuple[SourceFileInfo, ...],
    prefix_root: str = DEFAULT_STORAGE_PREFIX_ROOT,
) -> BronzeUploadResult:
    """Строит immutable bronze-ссылки для source package без сетевых вызовов."""

    storage_prefix = build_storage_prefix(experiment_id=experiment_id, prefix_root=prefix_root)
    stored_files = tuple(
        BronzeStoredSourceFile(
            name=source_file.name,
            relative_path=source_file.relative_path,
            bucket=bucket,
            object_key=build_object_key(
                storage_prefix=storage_prefix,
                relative_path=source_file.relative_path,
            ),
            size_bytes=source_file.size_bytes,
            sha256=source_file.sha256,
        )
        for source_file in source_files
    )

    return BronzeUploadResult(
        bucket=bucket,
        storage_prefix=storage_prefix,
        source_files=stored_files,
    )


def build_storage_prefix(*, experiment_id: str, prefix_root: str = DEFAULT_STORAGE_PREFIX_ROOT) -> str:
    """Возвращает prefix вида `eeg/{experiment_id}/` и проверяет path-safety."""

    if not EXPERIMENT_ID_PATTERN.fullmatch(experiment_id):
        raise BronzeStorageError("experiment_id has invalid format for object storage prefix")

    normalized_root = prefix_root.strip("/")
    if not normalized_root:
        return f"{experiment_id}/"

    root_path = PurePosixPath(normalized_root)
    if root_path.is_absolute() or ".." in root_path.parts:
        raise BronzeStorageError("storage prefix root must be a relative object-storage path")

    return f"{root_path.as_posix()}/{experiment_id}/"


def build_object_key(*, storage_prefix: str, relative_path: str) -> str:
    """Строит object key и не даёт relative_path выйти за пределы storage_prefix."""

    path = PurePosixPath(relative_path)
    if path.is_absolute() or ".." in path.parts or str(path) in {"", "."}:
        raise BronzeStorageError("source file relative_path must stay inside storage prefix")

    return f"{storage_prefix}{path.as_posix()}"


def parse_minio_endpoint(endpoint: str) -> tuple[str, bool]:
    """Преобразует `http://minio:9000` в параметры, которые ждёт MinIO SDK."""

    if "://" in endpoint:
        parsed = urlparse(endpoint)
        if parsed.scheme not in {"http", "https"}:
            raise BronzeStorageError("MINIO_ENDPOINT scheme must be http or https")
        if parsed.path not in {"", "/"}:
            raise BronzeStorageError("MINIO_ENDPOINT must not contain a path")
        if not parsed.netloc:
            raise BronzeStorageError("MINIO_ENDPOINT host is missing")
        return parsed.netloc, parsed.scheme == "https"

    if not endpoint or "/" in endpoint:
        raise BronzeStorageError("MINIO_ENDPOINT without scheme must be host[:port]")

    return endpoint, False


def guess_content_type(relative_path: str) -> str:
    """Возвращает стабильный content type для файлов EEG source package."""

    match Path(relative_path).name:
        case "signal.bin":
            return "application/octet-stream"
        case "experiment.json":
            return "application/json"
        case "journal.ndjson":
            return "application/x-ndjson"
        case "app.log":
            return "text/plain"
        case _:
            return "application/octet-stream"


def _ensure_source_files_exist(
    *,
    source_dir: Path,
    source_files: tuple[SourceFileInfo, ...],
) -> None:
    for source_file in source_files:
        file_path = source_dir / source_file.relative_path
        if not file_path.is_file():
            raise BronzeStorageError(f"source file is missing before bronze upload: {file_path}")


def _partial_bronze_result(
    result: BronzeUploadResult,
    uploaded: list[BronzeStoredSourceFile],
) -> BronzeUploadResult | None:
    """Строит результат из уже загруженных объектов для orphan-учёта при сбое."""

    if not uploaded:
        return None

    return BronzeUploadResult(
        bucket=result.bucket,
        storage_prefix=result.storage_prefix,
        source_files=tuple(uploaded),
    )
