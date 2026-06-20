"""Web-auth service для первого серверного стенда.

MVP использует HTTP-only cookie с подписанным session token. Это не требует
отдельной таблицы sessions и поэтому не залезает в зону DB owner. Позже этот
слой можно заменить на server-side sessions без изменения upload API.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import User


PASSWORD_HASH_ALGORITHM = "pbkdf2_sha256"
PASSWORD_HASH_ITERATIONS = 210_000


class AuthError(ValueError):
    """Базовая ошибка auth service."""


class InvalidCredentialsError(AuthError):
    """Login/password не прошли проверку."""


class InvalidSessionError(AuthError):
    """Session token отсутствует, испорчен или истёк."""


@dataclass(frozen=True)
class CurrentUser:
    """Минимальный user context, который нужен API endpoint'ам."""

    id: UUID
    username: str
    role: str


@dataclass(frozen=True)
class LoginResult:
    """Результат успешного login."""

    user: CurrentUser
    session_token: str
    expires_at: datetime


class AuthRepository(Protocol):
    """Минимальный контракт доступа к пользователям."""

    def get_active_user_by_username(self, username: str) -> User | None:
        """Возвращает активного пользователя по username."""

    def get_active_user_by_id(self, user_id: UUID) -> User | None:
        """Возвращает активного пользователя по UUID."""


class SqlAlchemyAuthRepository:
    """SQLAlchemy repository для таблицы users."""

    def __init__(self, db: Session) -> None:
        self._db = db

    def get_active_user_by_username(self, username: str) -> User | None:
        statement = select(User).where(
            User.username == username,
            User.is_active.is_(True),
        )
        return self._db.execute(statement).scalars().first()

    def get_active_user_by_id(self, user_id: UUID) -> User | None:
        statement = select(User).where(
            User.id == user_id,
            User.is_active.is_(True),
        )
        return self._db.execute(statement).scalars().first()


class AuthService:
    """Use cases для web-auth."""

    def __init__(
        self,
        *,
        repository: AuthRepository,
        auth_secret: str,
        session_ttl_hours: int,
        now: datetime | None = None,
    ) -> None:
        self._repository = repository
        self._auth_secret = auth_secret
        self._session_ttl_hours = session_ttl_hours
        self._now = now

    def login(self, *, username: str, password: str) -> LoginResult:
        """Проверяет login/password и создаёт signed session token."""

        user = self._repository.get_active_user_by_username(username)
        if user is None or not verify_password(password, user.password_hash):
            # Сообщение намеренно общее: наружу не раскрываем, существует ли username.
            raise InvalidCredentialsError("invalid username or password")

        current_user = _to_current_user(user)
        expires_at = self._current_time() + timedelta(hours=self._session_ttl_hours)
        session_token = self._build_session_token(current_user, expires_at)

        return LoginResult(
            user=current_user,
            session_token=session_token,
            expires_at=expires_at,
        )

    def authenticate_session_token(self, session_token: str | None) -> CurrentUser:
        """Проверяет cookie token и возвращает текущего пользователя."""

        if not session_token:
            raise InvalidSessionError("auth session cookie is missing")

        payload = self._decode_session_token(session_token)
        try:
            expires_at = datetime.fromtimestamp(int(payload["exp"]), tz=UTC)
        except (KeyError, TypeError, ValueError, OSError) as exc:
            raise InvalidSessionError("auth session expiry is invalid") from exc

        if expires_at <= self._current_time():
            raise InvalidSessionError("auth session expired")

        try:
            user_id = UUID(payload["sub"])
        except (KeyError, TypeError, ValueError) as exc:
            raise InvalidSessionError("auth session subject is invalid") from exc

        user = self._repository.get_active_user_by_id(user_id)
        if user is None:
            raise InvalidSessionError("auth session user is not active")

        return _to_current_user(user)

    def _build_session_token(self, user: CurrentUser, expires_at: datetime) -> str:
        payload = {
            "sub": str(user.id),
            "username": user.username,
            "role": user.role,
            "exp": int(expires_at.timestamp()),
        }
        encoded_payload = _base64url_encode(json.dumps(payload, separators=(",", ":")).encode())
        signature = _sign(encoded_payload, self._auth_secret)

        return f"{encoded_payload}.{signature}"

    def _decode_session_token(self, session_token: str) -> dict[str, object]:
        try:
            encoded_payload, signature = session_token.split(".", maxsplit=1)
        except ValueError as exc:
            raise InvalidSessionError("auth session token has invalid format") from exc

        expected_signature = _sign(encoded_payload, self._auth_secret)
        if not hmac.compare_digest(signature, expected_signature):
            raise InvalidSessionError("auth session signature is invalid")

        try:
            decoded_payload = _base64url_decode(encoded_payload)
            payload = json.loads(decoded_payload)
        except (binascii.Error, json.JSONDecodeError, ValueError) as exc:
            raise InvalidSessionError("auth session payload is invalid") from exc

        if not isinstance(payload, dict):
            raise InvalidSessionError("auth session payload is invalid")

        return payload

    def _current_time(self) -> datetime:
        return self._now or datetime.now(UTC)


def hash_password(password: str, *, salt: str | None = None) -> str:
    """Создаёт password hash в формате `pbkdf2_sha256$iterations$salt$hash`."""

    actual_salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        actual_salt.encode("utf-8"),
        PASSWORD_HASH_ITERATIONS,
    ).hex()

    return f"{PASSWORD_HASH_ALGORITHM}${PASSWORD_HASH_ITERATIONS}${actual_salt}${digest}"


def verify_password(password: str, password_hash: str) -> bool:
    """Проверяет пароль через constant-time сравнение digest'ов."""

    try:
        algorithm, iterations_text, salt, expected_digest = password_hash.split("$", maxsplit=3)
        iterations = int(iterations_text)
    except ValueError:
        return False

    if algorithm != PASSWORD_HASH_ALGORITHM:
        return False

    actual_digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        iterations,
    ).hex()

    return hmac.compare_digest(actual_digest, expected_digest)


def _to_current_user(user: User) -> CurrentUser:
    return CurrentUser(
        id=user.id,
        username=user.username,
        role=user.role,
    )


def _sign(encoded_payload: str, auth_secret: str) -> str:
    digest = hmac.new(
        auth_secret.encode("utf-8"),
        encoded_payload.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return _base64url_encode(digest)


def _base64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _base64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)
