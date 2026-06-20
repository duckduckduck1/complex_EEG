"""Readiness-проверки server-приложения.

`/health` отвечает только на вопрос "процесс жив?".
Этот модуль отвечает на другой вопрос: "можно ли уже принимать рабочий трафик?".

На первом стенде readiness проверяет PostgreSQL-соединение и host-директории,
которые нужны upload/validation/pipeline flow. Проверка миграций будет добавлена
отдельно, когда DB owner подготовит Alembic migration files.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import TypeAlias

from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError


DirectoryPath: TypeAlias = str | Path


@dataclass(frozen=True)
class ReadinessCheck:
    """Результат одной readiness-проверки."""

    name: str
    status: str
    message: str


@dataclass(frozen=True)
class ReadinessReport:
    """Итоговый readiness report для HTTP endpoint'а."""

    status: str
    checks: list[ReadinessCheck]

    @property
    def is_ready(self) -> bool:
        return self.status == "ready"


@dataclass(frozen=True)
class RequiredDirectory:
    """Директория, без которой server runtime не готов к работе."""

    name: str
    path: DirectoryPath
    require_write: bool = True


class ReadinessService:
    """Выполняет runtime-проверки готовности server-приложения."""

    def __init__(
        self,
        *,
        engine: Engine,
        required_directories: list[RequiredDirectory],
    ) -> None:
        self._engine = engine
        self._required_directories = required_directories

    def check(self) -> ReadinessReport:
        """Возвращает общий readiness report без выбрасывания HTTP-ошибок."""

        checks = [self._check_postgres()]
        checks.extend(
            self._check_directory(directory)
            for directory in self._required_directories
        )

        status = "ready" if all(check.status == "ok" for check in checks) else "not_ready"

        return ReadinessReport(status=status, checks=checks)

    def _check_postgres(self) -> ReadinessCheck:
        try:
            # `SELECT 1` проверяет именно доступность соединения.
            # Он не зависит от наличия таблиц и поэтому работает до миграций.
            with self._engine.connect() as connection:
                connection.execute(text("SELECT 1"))
        except SQLAlchemyError as exc:
            return ReadinessCheck(
                name="postgres",
                status="failed",
                message=f"PostgreSQL check failed: {exc.__class__.__name__}",
            )

        return ReadinessCheck(
            name="postgres",
            status="ok",
            message="PostgreSQL connection is available",
        )

    def _check_directory(self, directory: RequiredDirectory) -> ReadinessCheck:
        path = Path(directory.path)

        if not path.exists():
            return ReadinessCheck(
                name=directory.name,
                status="failed",
                message=f"Directory does not exist: {path}",
            )

        if not path.is_dir():
            return ReadinessCheck(
                name=directory.name,
                status="failed",
                message=f"Path is not a directory: {path}",
            )

        if directory.require_write and not os.access(path, os.W_OK):
            return ReadinessCheck(
                name=directory.name,
                status="failed",
                message=f"Directory is not writable: {path}",
            )

        return ReadinessCheck(
            name=directory.name,
            status="ok",
            message=f"Directory is available: {path}",
        )
