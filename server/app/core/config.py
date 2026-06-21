"""Конфигурация server-приложения.

Этот модуль собирает настройки приложения в одном месте.
Код приложения не должен знать, откуда пришли значения:
локально это могут быть дефолты, в Docker - .env, на сервере - Ansible/Vault.
"""

from urllib.parse import quote_plus

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Настройки приложения.

    BaseSettings читает значения из переменных окружения.
    Например, поле `postgres_user` можно переопределить через
    environment variable `POSTGRES_USER`.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "local"
    app_name: str = "complex_eeg_server"
    enable_local_upload_endpoint: bool = False
    log_level: str = "INFO"
    request_id_header: str = "X-Request-ID"
    auth_secret: SecretStr = SecretStr("change_me")
    session_cookie_name: str = "complex_eeg_session"
    session_ttl_hours: int = 12
    session_cookie_secure: bool = False

    postgres_host: str = "postgres"
    postgres_port: int = 5432
    postgres_db: str = "complex_eeg"
    postgres_user: str = "complex_eeg"
    postgres_password: SecretStr = SecretStr("change_me")

    experiments_dir: str = "/srv/complex_eeg/experiments"
    upload_tmp_dir: str = "/srv/complex_eeg/upload_tmp"
    pipeline_results_dir: str = "/srv/complex_eeg/pipeline_results"
    pipeline_version: str = "dev"
    pipeline_poll_interval_seconds: int = 5
    pipeline_max_run_duration_hours: int = 6
    pipeline_stuck_heartbeat_minutes: int = 15
    upload_session_ttl_hours: int = 24
    upload_max_size: int = 1024 * 1024 * 1024

    minio_endpoint: str = "http://minio:9000"
    minio_root_user: str = "minioadmin"
    minio_root_password: SecretStr = SecretStr("change_me")
    minio_bucket_bronze: str = "lakehouse-bronze"
    minio_bucket_silver: str = "lakehouse-silver"
    minio_bucket_gold: str = "lakehouse-gold"
    minio_bucket_derived: str = "lakehouse-derived"

    @property
    def database_url(self) -> str:
        """SQLAlchemy-compatible URL для подключения к PostgreSQL.

        Пароль кодируется через quote_plus, чтобы специальные символы
        вроде @, :, / или пробела не ломали строку подключения.
        """

        password = quote_plus(self.postgres_password.get_secret_value())

        return (
            "postgresql+psycopg://"
            f"{self.postgres_user}:{password}"
            f"@{self.postgres_host}:{self.postgres_port}"
            f"/{self.postgres_db}"
        )


# Один общий объект настроек, который импортируют другие части приложения.
settings = Settings()
