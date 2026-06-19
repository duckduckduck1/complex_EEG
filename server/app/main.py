"""Точка входа server-приложения.

Uvicorn будет запускать объект `app` из этого файла:
uvicorn app.main:app --reload
"""

from fastapi import FastAPI

from app.api.routes_health import router as health_router
from app.api.routes_upload import router as upload_router
from app.api.routes_upload_sessions import router as upload_sessions_router

app = FastAPI(title="complex_eeg_server")

# Подключаем route-модуль с /health и /ready.
# Позже рядом появятся upload, experiments, auth, web и pipeline routes.
app.include_router(health_router)
app.include_router(upload_sessions_router)
app.include_router(upload_router)
