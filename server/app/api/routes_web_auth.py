"""Web-auth endpoints для browser UI."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field

from app.api.deps_auth import get_auth_service, require_current_user
from app.core.config import settings
from app.features.auth import (
    AuthService,
    CurrentUser,
    InvalidCredentialsError,
)


router = APIRouter(prefix="/api/v1/web/auth", tags=["web-auth"])


class LoginRequest(BaseModel):
    """Login/password форма Web UI."""

    username: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=1)


class UserResponse(BaseModel):
    """Публичное представление пользователя без password_hash."""

    username: str
    role: str


class AuthResponse(BaseModel):
    """Ответ auth endpoint'ов."""

    user: UserResponse


@router.post("/login", response_model=AuthResponse)
def login(
    request: LoginRequest,
    response: Response,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthResponse:
    """Проверяет login/password и выставляет HTTP-only session cookie."""

    try:
        result = auth_service.login(
            username=request.username,
            password=request.password,
        )
    except InvalidCredentialsError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "auth.invalid_credentials",
                "message": "Invalid username or password",
            },
        ) from exc

    response.set_cookie(
        key=settings.session_cookie_name,
        value=result.session_token,
        max_age=settings.session_ttl_hours * 60 * 60,
        expires=int(result.expires_at.timestamp()),
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )

    return _auth_response(result.user)


@router.post("/logout")
def logout(response: Response) -> dict[str, str]:
    """Удаляет session cookie на стороне браузера."""

    response.delete_cookie(
        key=settings.session_cookie_name,
        path="/",
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
    )

    return {"status": "logged_out"}


@router.get("/me", response_model=AuthResponse)
def me(
    current_user: Annotated[CurrentUser, Depends(require_current_user)],
) -> AuthResponse:
    """Возвращает текущего аутентифицированного пользователя."""

    return _auth_response(current_user)


def _auth_response(user: CurrentUser) -> AuthResponse:
    return AuthResponse(
        user=UserResponse(
            username=user.username,
            role=user.role,
        )
    )
