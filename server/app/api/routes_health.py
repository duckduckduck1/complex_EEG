"""Health-check endpoint'ы сервера.

Эти endpoint'ы нужны не пользователю напрямую, а инфраструктуре:
Docker, nginx, CI/CD и мониторингу.
"""

from fastapi import APIRouter

from app.core.config import settings

router = APIRouter()


@router.get("/health")
def health() -> dict[str, str]:
    """Проверяет, что процесс приложения жив.

    /health отвечает "ok", если FastAPI-приложение запущено.
    На этом этапе мы не проверяем базу данных или файловую систему.
    """

    return {"status": "ok", "service": settings.app_name}


@router.get("/ready")
def ready() -> dict[str, str]:
    """Проверяет, готово ли приложение принимать трафик.

    Сейчас это заглушка. Позже /ready будет проверять PostgreSQL,
    доступность директорий и, возможно, состояние миграций.
    """

    return {"status": "ready"}