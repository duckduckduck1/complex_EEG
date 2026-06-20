"""Тесты runtime readiness-проверок."""

from __future__ import annotations

import shutil
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import create_engine
from sqlalchemy.exc import SQLAlchemyError

from app.features.readiness import ReadinessService, RequiredDirectory


class FailingEngine:
    """Engine-заглушка, которая имитирует недоступный PostgreSQL."""

    def connect(self):
        raise SQLAlchemyError("connection failed")


def _sqlite_engine():
    """Лёгкий engine для `SELECT 1` без реального PostgreSQL."""

    return create_engine("sqlite+pysqlite:///:memory:")


@pytest.fixture()
def workspace_tmp_path() -> Iterator[Path]:
    """Создаёт временную директорию внутри репозитория.

    На Windows-среде системный pytest tmp иногда недоступен по правам, поэтому
    держим временные файлы в рабочей области проекта.
    """

    root = Path(__file__).resolve().parents[1] / ".test_tmp" / uuid4().hex
    root.mkdir(parents=True, exist_ok=False)

    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_readiness_is_ready_when_database_and_directories_are_available(
    workspace_tmp_path: Path,
) -> None:
    """Готовность успешна, когда БД отвечает и директории доступны."""

    experiments_dir = workspace_tmp_path / "experiments"
    upload_tmp_dir = workspace_tmp_path / "upload_tmp"
    pipeline_results_dir = workspace_tmp_path / "pipeline_results"

    for directory in (experiments_dir, upload_tmp_dir, pipeline_results_dir):
        directory.mkdir()

    service = ReadinessService(
        engine=_sqlite_engine(),
        required_directories=[
            RequiredDirectory(name="experiments_dir", path=experiments_dir),
            RequiredDirectory(name="upload_tmp_dir", path=upload_tmp_dir),
            RequiredDirectory(name="pipeline_results_dir", path=pipeline_results_dir),
        ],
    )

    report = service.check()

    assert report.status == "ready"
    assert report.is_ready is True
    assert {check.name for check in report.checks} == {
        "postgres",
        "experiments_dir",
        "upload_tmp_dir",
        "pipeline_results_dir",
    }
    assert all(check.status == "ok" for check in report.checks)


def test_readiness_fails_when_database_is_unavailable(
    workspace_tmp_path: Path,
) -> None:
    """Недоступный PostgreSQL переводит report в not_ready."""

    experiments_dir = workspace_tmp_path / "experiments"
    experiments_dir.mkdir()

    service = ReadinessService(
        engine=FailingEngine(),
        required_directories=[
            RequiredDirectory(name="experiments_dir", path=experiments_dir),
        ],
    )

    report = service.check()

    assert report.status == "not_ready"
    assert report.is_ready is False
    assert report.checks[0].name == "postgres"
    assert report.checks[0].status == "failed"


def test_readiness_fails_when_required_directory_is_missing(
    workspace_tmp_path: Path,
) -> None:
    """Отсутствующая runtime-директория делает приложение not_ready."""

    service = ReadinessService(
        engine=_sqlite_engine(),
        required_directories=[
            RequiredDirectory(
                name="upload_tmp_dir",
                path=workspace_tmp_path / "missing_upload_tmp",
            ),
        ],
    )

    report = service.check()

    assert report.status == "not_ready"
    assert report.checks[1].name == "upload_tmp_dir"
    assert report.checks[1].status == "failed"
