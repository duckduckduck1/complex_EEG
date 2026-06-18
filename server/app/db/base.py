"""Базовый слой SQLAlchemy-моделей.

Все ORM-модели приложения будут наследоваться от Base.
Это нужно, чтобы Alembic мог видеть таблицы и генерировать миграции.
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Общий declarative base для таблиц приложения."""