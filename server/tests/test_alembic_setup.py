"""Тесты Alembic-конфигурации.

Эти тесты не подключаются к PostgreSQL.
Их задача - проверить, что Alembic-структура проекта собрана корректно.
"""

from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory


SERVER_ROOT = Path(__file__).resolve().parents[1]


def test_alembic_script_location_is_valid() -> None:
    """Alembic должен видеть папку с будущими migration-файлами."""

    config = Config(str(SERVER_ROOT / "alembic.ini"))
    script = ScriptDirectory.from_config(config)

    assert Path(script.versions).resolve() == (
        SERVER_ROOT / "alembic" / "versions"
    ).resolve()
    assert script.get_heads() == []


def test_alembic_ini_uses_placeholder_database_url() -> None:
    """alembic.ini не должен хранить реальные доступы к PostgreSQL."""

    config = Config(str(SERVER_ROOT / "alembic.ini"))

    assert config.get_main_option("sqlalchemy.url") == (
        "postgresql+psycopg://"
        "placeholder:placeholder"
        "@localhost:5432"
        "/placeholder"
    )


def test_alembic_env_uses_application_settings() -> None:
    """env.py должен брать DATABASE_URL из Settings, а не из ini-файла."""

    env_py = SERVER_ROOT / "alembic" / "env.py"
    env_source = env_py.read_text(encoding="utf-8")

    assert "from app.core.config import settings" in env_source
    assert 'config.set_main_option("sqlalchemy.url", settings.database_url)' in env_source
    assert "from app.db import models" in env_source