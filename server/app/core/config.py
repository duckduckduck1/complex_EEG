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

    postgres_host: str = "postgres"
    postgres_port: int = 5432
    postgres_db: str = "complex_eeg"
    postgres_user: str = "complex_eeg"
    postgres_password: SecretStr = SecretStr("change_me")

    experiments_dir: str = "/srv/complex_eeg/experiments"
    upload_tmp_dir: str = "/srv/complex_eeg/upload_tmp"
    pipeline_results_dir: str = "/srv/complex_eeg/pipeline_results"

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
