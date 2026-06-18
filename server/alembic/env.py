"""Alembic environment.

Этот файл запускается Alembic при командах upgrade/downgrade/revision.
Он связывает Alembic с настройками приложения и SQLAlchemy metadata.
"""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.config import settings
from app.db.base import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Alembic сравнивает target_metadata с реальной БД при autogenerate.
# Сейчас моделей ещё нет, поэтому metadata пустая.
target_metadata = Base.metadata

# Не храним URL подключения в alembic.ini.
# Alembic получает его из того же Settings-класса, что и приложение.
config.set_main_option("sqlalchemy.url", settings.database_url)


def run_migrations_offline() -> None:
    """Запускает миграции без подключения к БД.

    Offline mode генерирует SQL-скрипт, но не выполняет его.
    На первом стенде чаще будем использовать online mode.
    """

    url = config.get_main_option("sqlalchemy.url")

    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Запускает миграции с реальным подключением к PostgreSQL."""

    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()