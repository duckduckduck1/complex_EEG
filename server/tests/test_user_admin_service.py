"""Тесты служебного создания пользователей Web UI."""

from __future__ import annotations

from uuid import uuid4

import pytest

from app.db.models import User
from app.features.auth import hash_password, verify_password
from app.features.user_admin import (
    InvalidUsernameError,
    InvalidUserRoleError,
    UserAdminService,
    UsernameAlreadyExistsError,
    WeakPasswordError,
)


class FakeUserAdminRepository:
    """In-memory repository, чтобы тесты не требовали PostgreSQL."""

    def __init__(self, users: list[User] | None = None) -> None:
        self.users = users or []

    def get_user_by_username(self, username: str) -> User | None:
        for user in self.users:
            if user.username == username:
                return user
        return None

    def add_user(self, user: User) -> User:
        if self.get_user_by_username(user.username) is not None:
            raise UsernameAlreadyExistsError(f"user '{user.username}' already exists")

        # В настоящей БД UUID появится во время flush. В fake repository
        # имитируем это поведение вручную.
        if user.id is None:
            user.id = uuid4()

        self.users.append(user)
        return user


def _existing_user(username: str = "admin") -> User:
    return User(
        id=uuid4(),
        username=username,
        password_hash=hash_password("existing-password"),
        role="admin",
        is_active=True,
    )


def test_create_user_hashes_password_and_returns_public_result() -> None:
    """Service создаёт активного пользователя и не хранит plain text пароль."""

    repository = FakeUserAdminRepository()
    service = UserAdminService(repository)
    password = "very-secure-password"

    result = service.create_user(
        username=" admin ",
        password=password,
        role="admin",
    )

    assert result.username == "admin"
    assert result.role == "admin"
    assert result.is_active is True

    saved_user = repository.users[0]
    assert saved_user.password_hash != password
    assert verify_password(password, saved_user.password_hash)


def test_create_user_rejects_duplicate_username() -> None:
    """Username должен оставаться уникальным."""

    repository = FakeUserAdminRepository([_existing_user("admin")])
    service = UserAdminService(repository)

    with pytest.raises(UsernameAlreadyExistsError):
        service.create_user(
            username="admin",
            password="very-secure-password",
            role="admin",
        )


def test_create_user_rejects_invalid_username() -> None:
    """Username не должен содержать пробелы и path-like символы."""

    service = UserAdminService(FakeUserAdminRepository())

    with pytest.raises(InvalidUsernameError):
        service.create_user(
            username="bad username",
            password="very-secure-password",
            role="admin",
        )


def test_create_user_rejects_invalid_role() -> None:
    """Role ограничена ролями Web UI первого стенда."""

    service = UserAdminService(FakeUserAdminRepository())

    with pytest.raises(InvalidUserRoleError):
        service.create_user(
            username="admin",
            password="very-secure-password",
            role="superuser",
        )


def test_create_user_rejects_weak_password() -> None:
    """Служебный пользователь не должен создаваться с коротким паролем."""

    service = UserAdminService(FakeUserAdminRepository())

    with pytest.raises(WeakPasswordError):
        service.create_user(
            username="admin",
            password="short",
            role="admin",
        )
