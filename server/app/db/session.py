"""Подключение к PostgreSQL через SQLAlchemy.

Этот модуль не описывает таблицы. Его задача - создать engine,
фабрику DB-сессий и dependency для FastAPI endpoint'ов.
"""

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

# Engine управляет соединениями с PostgreSQL.
# Важно: create_engine сам по себе обычно не открывает сетевое соединение.
# Реальное подключение происходит, когда выполняется SQL-запрос.
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
)

# SessionLocal - фабрика сессий.
# Каждый HTTP-запрос должен получать свою отдельную сессию.
SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,
    autoflush=False,
)


def get_db_session() -> Generator[Session, None, None]:
    """Создаёт DB-сессию на время обработки одного запроса.

    FastAPI будет использовать эту функцию как dependency.
    Блок finally гарантирует, что сессия закроется даже при ошибке внутри endpoint.
    """

    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()