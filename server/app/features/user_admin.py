"""Use cases для управления пользователями Web UI.

Этот модуль нужен не для публичной регистрации, а для служебного сценария:
оператор стенда создаёт первого пользователя через CLI после применения
миграций БД. Поэтому здесь нет HTTP-контроллеров и нет self-signup логики.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Protocol
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.models import User
from app.features.auth import hash_password


ALLOWED_USER_ROLES = frozenset({"viewer", "operator", "admin"})
MIN_PASSWORD_LENGTH = 12
USERNAME_PATTERN = re.compile(r"^[a-zA-Z0-9_.@-]{1,128}$")


class UserAdminError(ValueError):
    """Базовая ошибка служебного управления пользователями."""


class InvalidUsernameError(UserAdminError):
    """Username не соответствует безопасному формату."""


class InvalidUserRoleError(UserAdminError):
    """Role не входит в разрешённый список ролей Web UI."""


class WeakPasswordError(UserAdminError):
    """Пароль слишком короткий для служебного пользователя."""


class UsernameAlreadyExistsError(UserAdminError):
    """Пользователь с таким username уже существует."""


@dataclass(frozen=True)
class CreatedUser:
    """Публичный результат создания пользователя без password_hash."""

    id: UUID
    username: str
    role: str
    is_active: bool


class UserAdminRepository(Protocol):
    """Минимальный контракт repository для user-admin use cases."""

    def get_user_by_username(self, username: str) -> User | None:
        """Возвращает пользователя по username, включая inactive."""

    def add_user(self, user: User) -> User:
        """Добавляет пользователя и возвращает объект после flush."""


class SqlAlchemyUserAdminRepository:
    """SQLAlchemy repository для таблицы `users`."""

    def __init__(self, db: Session) -> None:
        self._db = db

    def get_user_by_username(self, username: str) -> User | None:
        statement = select(User).where(User.username == username)
        return self._db.execute(statement).scalars().first()

    def add_user(self, user: User) -> User:
        self._db.add(user)

        try:
            # Flush отправляет INSERT в БД до commit. Так мы сразу ловим unique
            # constraint по username и получаем UUID, сгенерированный моделью.
            self._db.flush()
        except IntegrityError as exc:
            self._db.rollback()
            raise UsernameAlreadyExistsError(
                f"user '{user.username}' already exists"
            ) from exc

        return user


class UserAdminService:
    """Служебные операции над пользователями Web UI."""

    def __init__(self, repository: UserAdminRepository) -> None:
        self._repository = repository

    def create_user(self, *, username: str, password: str, role: str) -> CreatedUser:
        """Создаёт активного пользователя с hash'ем пароля.

        Пароль в plain text нужен только на входе в этот метод. В БД уходит
        только `password_hash`, совместимый с `AuthService.login`.
        """

        normalized_username = _normalize_username(username)
        _validate_username(normalized_username)
        _validate_role(role)
        _validate_password(password)

        if self._repository.get_user_by_username(normalized_username) is not None:
            raise UsernameAlreadyExistsError(
                f"user '{normalized_username}' already exists"
            )

        user = User(
            username=normalized_username,
            password_hash=hash_password(password),
            role=role,
            is_active=True,
        )
        saved_user = self._repository.add_user(user)

        return CreatedUser(
            id=saved_user.id,
            username=saved_user.username,
            role=saved_user.role,
            is_active=saved_user.is_active,
        )


def _normalize_username(username: str) -> str:
    return username.strip()


def _validate_username(username: str) -> None:
    if not USERNAME_PATTERN.fullmatch(username):
        raise InvalidUsernameError(
            "username must match ^[a-zA-Z0-9_.@-]{1,128}$"
        )


def _validate_role(role: str) -> None:
    if role not in ALLOWED_USER_ROLES:
        allowed = ", ".join(sorted(ALLOWED_USER_ROLES))
        raise InvalidUserRoleError(f"role must be one of: {allowed}")


def _validate_password(password: str) -> None:
    if len(password) < MIN_PASSWORD_LENGTH:
        raise WeakPasswordError(
            f"password must be at least {MIN_PASSWORD_LENGTH} characters long"
        )
