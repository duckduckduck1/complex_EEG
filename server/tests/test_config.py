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


def test_upload_session_ttl_hours_uses_environment_value(monkeypatch) -> None:
    """TTL upload session должен настраиваться через environment variable."""

    monkeypatch.setenv("UPLOAD_SESSION_TTL_HOURS", "12")

    settings = Settings()

    assert settings.upload_session_ttl_hours == 12


def test_upload_max_size_uses_environment_value(monkeypatch) -> None:
    """Максимальный размер upload-файла должен задаваться через env."""

    monkeypatch.setenv("UPLOAD_MAX_SIZE", "4096")

    settings = Settings()

    assert settings.upload_max_size == 4096


def test_auth_settings_use_environment_values(monkeypatch) -> None:
    """Auth-настройки должны быть управляемыми через env для Docker/VM."""

    monkeypatch.setenv("AUTH_SECRET", "test-secret")
    monkeypatch.setenv("SESSION_COOKIE_NAME", "test_session")
    monkeypatch.setenv("SESSION_TTL_HOURS", "2")
    monkeypatch.setenv("SESSION_COOKIE_SECURE", "true")

    settings = Settings()

    assert settings.auth_secret.get_secret_value() == "test-secret"
    assert settings.session_cookie_name == "test_session"
    assert settings.session_ttl_hours == 2
    assert settings.session_cookie_secure is True


def test_logging_settings_use_environment_values(monkeypatch) -> None:
    """Logging-настройки должны управляться через env для Docker runtime."""

    monkeypatch.setenv("LOG_LEVEL", "DEBUG")
    monkeypatch.setenv("REQUEST_ID_HEADER", "X-Correlation-ID")

    settings = Settings()

    assert settings.log_level == "DEBUG"
    assert settings.request_id_header == "X-Correlation-ID"


def test_pipeline_settings_use_environment_values(monkeypatch) -> None:
    """Pipeline-настройки должны приходить из env для API и будущего worker."""

    monkeypatch.setenv("PIPELINE_VERSION", "2026.06.21-test")
    monkeypatch.setenv("PIPELINE_POLL_INTERVAL_SECONDS", "3")
    monkeypatch.setenv("PIPELINE_MAX_RUN_DURATION_HOURS", "8")
    monkeypatch.setenv("PIPELINE_STUCK_HEARTBEAT_MINUTES", "20")

    settings = Settings()

    assert settings.pipeline_version == "2026.06.21-test"
    assert settings.pipeline_poll_interval_seconds == 3
    assert settings.pipeline_max_run_duration_hours == 8
    assert settings.pipeline_stuck_heartbeat_minutes == 20
