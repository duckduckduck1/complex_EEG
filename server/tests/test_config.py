"""Тесты конфигурации приложения.

Мы проверяем, что настройки можно переопределять через environment variables.
Это важно для Docker, CI/CD и деплоя на сервер.
"""

from app.core.config import Settings


def test_database_url_uses_default_values() -> None:
    """Settings должен собирать DATABASE_URL из дефолтных значений."""

    settings = Settings()

    assert settings.database_url == (
        "postgresql+psycopg://"
        "complex_eeg:change_me"
        "@postgres:5432"
        "/complex_eeg"
    )


def test_database_url_uses_environment_values(monkeypatch) -> None:
    """Environment variables должны переопределять дефолтные значения."""

    monkeypatch.setenv("POSTGRES_HOST", "localhost")
    monkeypatch.setenv("POSTGRES_PORT", "15432")
    monkeypatch.setenv("POSTGRES_DB", "test_db")
    monkeypatch.setenv("POSTGRES_USER", "test_user")
    monkeypatch.setenv("POSTGRES_PASSWORD", "pa:ss@word")

    settings = Settings()

    assert settings.database_url == (
        "postgresql+psycopg://"
        "test_user:pa%3Ass%40word"
        "@localhost:15432"
        "/test_db"
    )