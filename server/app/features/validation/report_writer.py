"""Запись отчёта валидации в JSON-файл.

Валидатор возвращает ValidationResult в памяти.
Этот модуль превращает результат проверки в диагностический файл на диске.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from app.features.validation.package_validator import ValidationResult


def build_validation_report(result: ValidationResult) -> dict[str, Any]:
    """Собирает JSON-совместимый словарь отчёта.

    Мы отделяем сборку данных от записи файла, чтобы эту функцию было удобно
    тестировать без filesystem.
    """

    return {
        "experiment_id": result.experiment_id,
        "status": result.status,
        # UTC упрощает разбор логов и отчётов на сервере, в Docker и в CI.
        "checked_at": datetime.now(UTC).isoformat(),
        "signal_size_bytes": result.signal_size_bytes,
        "sample_count": result.sample_count,
        "warnings": result.warnings,
        "errors": [asdict(error) for error in result.errors],
    }


def write_validation_report(
    result: ValidationResult,
    report_path: str | Path,
) -> Path:
    """Сохраняет результат валидации в JSON-отчёт.

    Отчёт нужен для Web UI, логов, ручной диагностики и будущего разбора
    проблемных загрузок. Функция сама создаёт родительскую директорию.
    """

    destination = Path(report_path)

    # Родительская директория может ещё не существовать после новой загрузки.
    destination.parent.mkdir(parents=True, exist_ok=True)

    report = build_validation_report(result)

    destination.write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    return destination