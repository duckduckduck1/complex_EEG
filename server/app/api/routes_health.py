"""Health-check endpoint'ы сервера.

Эти endpoint'ы нужны не пользователю напрямую, а инфраструктуре:
Docker, nginx, CI/CD и мониторингу.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.db.session import engine
from app.features.readiness import ReadinessReport, ReadinessService, RequiredDirectory

router = APIRouter()


@router.get("/health")
def health() -> dict[str, str]:
    """Проверяет, что процесс приложения жив.

    /health отвечает "ok", если FastAPI-приложение запущено.
    На этом этапе мы не проверяем базу данных или файловую систему.
    """

    return {"status": "ok", "service": settings.app_name}


def get_readiness_service() -> ReadinessService:
    """Собирает readiness service из runtime-настроек приложения."""

    return ReadinessService(
        engine=engine,
        required_directories=[
            RequiredDirectory(name="experiments_dir", path=settings.experiments_dir),
            RequiredDirectory(name="upload_tmp_dir", path=settings.upload_tmp_dir),
            RequiredDirectory(
                name="pipeline_results_dir",
                path=settings.pipeline_results_dir,
            ),
        ],
    )


@router.get("/ready", response_model=None)
def ready(
    readiness_service: Annotated[ReadinessService, Depends(get_readiness_service)],
) -> dict[str, object] | JSONResponse:
    """Проверяет, готово ли приложение принимать трафик.

    /ready строже, чем /health: он проверяет PostgreSQL и директории, без
    которых upload/validation/pipeline flow не сможет работать.
    """

    report = readiness_service.check()
    body = _readiness_body(report)

    if report.is_ready:
        return body

    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content=body,
    )


def _readiness_body(report: ReadinessReport) -> dict[str, object]:
    return {
        "status": report.status,
        "checks": [
            {
                "name": check.name,
                "status": check.status,
                "message": check.message,
            }
            for check in report.checks
        ],
    }
