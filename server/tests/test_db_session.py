"""Тесты базового DB-слоя.

Эти тесты не подключаются к реальной PostgreSQL.
Мы проверяем только, что SQLAlchemy-слой корректно создаётся.
"""

from sqlalchemy.orm import Session

from app.db.base import Base
from app.db.session import engine, get_db_session


def test_base_has_metadata() -> None:
    """Base должен иметь metadata для будущих Alembic-миграций."""

    assert Base.metadata is not None


def test_engine_uses_postgresql_psycopg_driver() -> None:
    """Engine должен использовать PostgreSQL-драйвер psycopg."""

    assert engine.url.drivername == "postgresql+psycopg"
    assert engine.url.database == "complex_eeg"


def test_get_db_session_yields_sqlalchemy_session() -> None:
    """FastAPI dependency должна выдавать SQLAlchemy Session."""

    dependency = get_db_session()
    db = next(dependency)

    try:
        assert isinstance(db, Session)
    finally:
        dependency.close()