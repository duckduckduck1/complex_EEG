"""Тесты web-auth service без реальной БД."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

from app.db.models import User
from app.features.auth import (
    AuthService,
    InvalidCredentialsError,
    InvalidSessionError,
    hash_password,
    verify_password,
)


FIXED_NOW = datetime(2026, 6, 20, 12, 0, tzinfo=UTC)
AUTH_SECRET = "test_secret"


class FakeAuthRepository:
    """In-memory users repository для auth unit tests."""

    def __init__(self, users: list[User] | None = None) -> None:
        self.users = users or []

    def get_active_user_by_username(self, username: str) -> User | None:
        for user in self.users:
            if user.username == username and user.is_active:
                return user
        return None

    def get_active_user_by_id(self, user_id: UUID) -> User | None:
        for user in self.users:
            if user.id == user_id and user.is_active:
                return user
        return None


def _user(
    *,
    username: str = "lab_user",
    password: str = "correct-password",
    is_active: bool = True,
) -> User:
    return User(
        id=uuid4(),
        username=username,
        password_hash=hash_password(password, salt="fixed_salt"),
        role="operator",
        is_active=is_active,
    )


def _service(repository: FakeAuthRepository, *, now: datetime = FIXED_NOW) -> AuthService:
    return AuthService(
        repository=repository,
        auth_secret=AUTH_SECRET,
        session_ttl_hours=12,
        now=now,
    )


def test_hash_password_verifies_correct_password() -> None:
    """Пароль проверяется по hash, а не хранится в plain text."""

    password_hash = hash_password("secret", salt="fixed_salt")

    assert password_hash != "secret"
    assert verify_password("secret", password_hash)
    assert not verify_password("wrong", password_hash)


def test_login_returns_session_token_and_current_user() -> None:
    """Успешный login возвращает signed token и user context."""

    repository = FakeAuthRepository([_user()])
    service = _service(repository)

    result = service.login(username="lab_user", password="correct-password")

    assert result.user.username == "lab_user"
    assert result.user.role == "operator"
    assert result.session_token
    assert result.expires_at == FIXED_NOW + timedelta(hours=12)


def test_session_token_authenticates_current_user() -> None:
    """Token из login можно использовать для восстановления current user."""

    user = _user()
    repository = FakeAuthRepository([user])
    service = _service(repository)
    login_result = service.login(username=user.username, password="correct-password")

    current_user = service.authenticate_session_token(login_result.session_token)

    assert current_user.id == user.id
    assert current_user.username == user.username


def test_login_rejects_invalid_credentials() -> None:
    """Неверный пароль не должен создавать session token."""

    repository = FakeAuthRepository([_user()])
    service = _service(repository)

    with pytest.raises(InvalidCredentialsError):
        service.login(username="lab_user", password="wrong")


def test_session_token_rejects_tampering() -> None:
    """Подпись защищает cookie token от ручного изменения."""

    repository = FakeAuthRepository([_user()])
    service = _service(repository)
    login_result = service.login(username="lab_user", password="correct-password")
    tampered_token = login_result.session_token + "x"

    with pytest.raises(InvalidSessionError):
        service.authenticate_session_token(tampered_token)


def test_session_token_rejects_expired_token() -> None:
    """Просроченная cookie session не проходит проверку."""

    user = _user()
    repository = FakeAuthRepository([user])
    login_service = _service(repository)
    login_result = login_service.login(username=user.username, password="correct-password")
    expired_service = _service(repository, now=FIXED_NOW + timedelta(hours=13))

    with pytest.raises(InvalidSessionError):
        expired_service.authenticate_session_token(login_result.session_token)


def test_session_token_rejects_inactive_user() -> None:
    """Если пользователя деактивировали, старый token больше не принимается."""

    user = _user()
    repository = FakeAuthRepository([user])
    service = _service(repository)
    login_result = service.login(username=user.username, password="correct-password")
    user.is_active = False

    with pytest.raises(InvalidSessionError):
        service.authenticate_session_token(login_result.session_token)
