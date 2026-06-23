"""Auth dependencies для FastAPI endpoint'ов."""

from __future__ import annotations

import base64
import hashlib
import hmac
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db_session
from app.features.auth import (
    AuthService,
    CurrentUser,
    InvalidSessionError,
    SqlAlchemyAuthRepository,
)


CSRF_HEADER_NAME = "X-CSRF-Token"


def get_auth_service(
    db: Annotated[Session, Depends(get_db_session)],
) -> AuthService:
    """Собирает auth service для одного HTTP request."""

    return AuthService(
        repository=SqlAlchemyAuthRepository(db),
        auth_secret=settings.auth_secret.get_secret_value(),
        session_ttl_hours=settings.session_ttl_hours,
    )


def require_current_user(
    request: Request,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> CurrentUser:
    """FastAPI dependency, которая требует валидную web session cookie."""

    session_token = request.cookies.get(settings.session_cookie_name)

    try:
        return auth_service.authenticate_session_token(session_token)
    except InvalidSessionError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "auth.required",
                "message": str(exc),
            },
        ) from exc


def build_csrf_token(session_token: str) -> str:
    """Строит stateless CSRF token, привязанный к web session cookie."""

    digest = hmac.new(
        settings.auth_secret.get_secret_value().encode("utf-8"),
        f"csrf:{session_token}".encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def require_csrf_token(request: Request) -> None:
    """Проверяет CSRF token для browser SPA mutating requests."""

    session_token = request.cookies.get(settings.session_cookie_name)
    if not session_token:
        # Auth dependency вернёт 401 для production request. Такой early return
        # оставляет unit tests с dependency override простыми и не ослабляет
        # реальные cookie-auth запросы.
        return

    csrf_token = request.headers.get(CSRF_HEADER_NAME)
    if not csrf_token or not hmac.compare_digest(csrf_token, build_csrf_token(session_token)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "auth.csrf_required",
                "message": "CSRF token is missing or invalid",
            },
        )
