"""Auth dependencies для FastAPI endpoint'ов."""

from __future__ import annotations

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
