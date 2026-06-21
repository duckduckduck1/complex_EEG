"""Тесты MinIO bronze storage adapter без реального MinIO."""

from __future__ import annotations

import shutil
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest

from app.features.upload.bronze_storage import (
    BronzeStorageError,
    MinioBronzeObjectStorage,
    NoopBronzeObjectStorage,
    build_object_key,
    build_storage_prefix,
    guess_content_type,
    parse_minio_endpoint,
)
from app.features.upload.file_inventory import SourceFileInfo


class FakeMinioClient:
    """Запоминает fput_object вызовы вместо сетевой загрузки."""

    def __init__(self) -> None:
        self.uploads: list[dict[str, str]] = []
        self.stats: list[dict[str, str]] = []

    def fput_object(
        self,
        *,
        bucket_name: str,
        object_name: str,
        file_path: str,
        content_type: str,
    ) -> None:
        self.uploads.append(
            {
                "bucket_name": bucket_name,
                "object_name": object_name,
                "file_path": file_path,
                "content_type": content_type,
            }
        )

    def stat_object(
        self,
        *,
        bucket_name: str,
        object_name: str,
    ) -> None:
        self.stats.append(
            {
                "bucket_name": bucket_name,
                "object_name": object_name,
            }
        )


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт временную директорию внутри repo, а не в закрытом Windows Temp."""

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_noop_bronze_storage_builds_stable_object_keys(workspace_tmp_path: Path) -> None:
    """Noop adapter строит те же ссылки, что production adapter, но без сети."""

    source_dir = workspace_tmp_path / "source"
    source_dir.mkdir()
    (source_dir / "signal.bin").write_bytes(b"\x00\x00\x00\x00")

    storage = NoopBronzeObjectStorage(bucket="lakehouse-bronze")
    result = storage.upload_source_package(
        experiment_id="exp_01",
        source_dir=source_dir,
        source_files=(
            SourceFileInfo(
                name="signal.bin",
                relative_path="signal.bin",
                size_bytes=4,
                sha256="0" * 64,
            ),
        ),
    )

    assert result.bucket == "lakehouse-bronze"
    assert result.storage_prefix == "eeg/exp_01/"
    assert result.source_files[0].object_key == "eeg/exp_01/signal.bin"


def test_minio_bronze_storage_uploads_each_source_file(workspace_tmp_path: Path) -> None:
    """Production adapter вызывает MinIO fput_object для каждого source-файла."""

    source_dir = workspace_tmp_path / "source"
    source_dir.mkdir()
    (source_dir / "signal.bin").write_bytes(b"\x00\x00\x00\x00")
    (source_dir / "experiment.json").write_text("{}", encoding="utf-8")

    client = FakeMinioClient()
    storage = MinioBronzeObjectStorage(client=client, bucket="lakehouse-bronze")

    result = storage.upload_source_package(
        experiment_id="exp_01",
        source_dir=source_dir,
        source_files=(
            SourceFileInfo(
                name="experiment.json",
                relative_path="experiment.json",
                size_bytes=2,
                sha256="1" * 64,
            ),
            SourceFileInfo(
                name="signal.bin",
                relative_path="signal.bin",
                size_bytes=4,
                sha256="0" * 64,
            ),
        ),
    )

    assert result.storage_prefix == "eeg/exp_01/"
    assert [upload["object_name"] for upload in client.uploads] == [
        "eeg/exp_01/experiment.json",
        "eeg/exp_01/signal.bin",
    ]
    assert [stat["object_name"] for stat in client.stats] == [
        "eeg/exp_01/experiment.json",
        "eeg/exp_01/signal.bin",
    ]
    assert client.uploads[0]["content_type"] == "application/json"
    assert client.uploads[1]["content_type"] == "application/octet-stream"


def test_minio_bronze_storage_wraps_client_errors(workspace_tmp_path: Path) -> None:
    """Ошибки SDK наружу выходят как доменная BronzeStorageError."""

    class FailingMinioClient:
        def fput_object(self, **kwargs: object) -> None:
            raise RuntimeError("network failed")

    source_dir = workspace_tmp_path / "source"
    source_dir.mkdir()
    (source_dir / "signal.bin").write_bytes(b"\x00\x00\x00\x00")
    storage = MinioBronzeObjectStorage(client=FailingMinioClient(), bucket="lakehouse-bronze")

    with pytest.raises(BronzeStorageError):
        storage.upload_source_package(
            experiment_id="exp_01",
            source_dir=source_dir,
            source_files=(
                SourceFileInfo(
                    name="signal.bin",
                    relative_path="signal.bin",
                    size_bytes=4,
                    sha256="0" * 64,
                ),
            ),
        )


def test_minio_bronze_storage_requires_uploaded_objects_to_be_readable(
    workspace_tmp_path: Path,
) -> None:
    """Accepted upload нельзя строить на object keys, которые MinIO не отдаёт обратно."""

    class MissingAfterUploadClient:
        def fput_object(self, **kwargs: object) -> None:
            return None

        def stat_object(self, **kwargs: object) -> None:
            raise RuntimeError("object not found")

    source_dir = workspace_tmp_path / "source"
    source_dir.mkdir()
    (source_dir / "signal.bin").write_bytes(b"\x00\x00\x00\x00")
    storage = MinioBronzeObjectStorage(client=MissingAfterUploadClient(), bucket="lakehouse-bronze")

    with pytest.raises(BronzeStorageError):
        storage.upload_source_package(
            experiment_id="exp_01",
            source_dir=source_dir,
            source_files=(
                SourceFileInfo(
                    name="signal.bin",
                    relative_path="signal.bin",
                    size_bytes=4,
                    sha256="0" * 64,
                ),
            ),
        )


def test_object_key_helpers_reject_path_traversal() -> None:
    """experiment_id и relative_path не должны превращаться в произвольный object key."""

    with pytest.raises(BronzeStorageError):
        build_storage_prefix(experiment_id="../bad")

    with pytest.raises(BronzeStorageError):
        build_object_key(storage_prefix="eeg/exp_01/", relative_path="../signal.bin")


def test_parse_minio_endpoint_supports_http_and_https() -> None:
    """MINIO_ENDPOINT хранится как URL, а SDK ждёт host:port + secure flag."""

    assert parse_minio_endpoint("http://minio:9000") == ("minio:9000", False)
    assert parse_minio_endpoint("https://minio.example.com") == ("minio.example.com", True)
    assert parse_minio_endpoint("minio:9000") == ("minio:9000", False)


def test_guess_content_type_uses_eeg_source_file_contract() -> None:
    """Content-Type фиксирован для известных файлов EEG source package."""

    assert guess_content_type("signal.bin") == "application/octet-stream"
    assert guess_content_type("experiment.json") == "application/json"
    assert guess_content_type("journal.ndjson") == "application/x-ndjson"
    assert guess_content_type("app.log") == "text/plain"
