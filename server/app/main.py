"""Точка входа server-приложения.

Uvicorn будет запускать объект `app` из этого файла:
uvicorn app.main:app --reload
"""

from fastapi import FastAPI

from app.api.routes_health import router as health_router
from app.api.routes_upload import router as upload_router
from app.api.routes_upload_sessions import router as upload_sessions_router
from app.api.routes_web_auth import router as web_auth_router
from app.api.routes_web_experiments import router as web_experiments_router
from app.api.routes_web_pipeline import router as web_pipeline_router
from app.core.config import settings
from app.core.logging import RequestLoggingMiddleware, configure_logging

configure_logging(settings.log_level)
app = FastAPI(title="complex_eeg_server")
app.add_middleware(
    RequestLoggingMiddleware,
    request_id_header=settings.request_id_header,
)

# Подключаем route-модули явно: так проще видеть публичную поверхность API.
# Новые крупные зоны добавляем отдельными routers, не смешивая их в main.py.
app.include_router(health_router)
app.include_router(web_auth_router)
app.include_router(web_experiments_router)
app.include_router(web_pipeline_router)
app.include_router(upload_sessions_router)
app.include_router(upload_router)
