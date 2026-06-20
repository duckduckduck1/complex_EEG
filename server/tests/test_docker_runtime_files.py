"""Статические проверки Docker runtime-файлов.

Эти тесты не заменяют `docker compose build` на VM. Их задача проще: поймать
случайный возврат к placeholder-команде или поломку proxy path ещё до ручной
проверки в Docker.
"""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_api_compose_service_runs_real_fastapi_app() -> None:
    """API service должен запускать uvicorn, а не временный http.server."""

    compose = (REPO_ROOT / "docker-compose.yml").read_text(encoding="utf-8")

    assert "context: ./server" in compose
    assert "dockerfile: Dockerfile" in compose
    assert "uvicorn" in compose
    assert "app.main:app" in compose
    assert "http.server" not in compose
    assert "http://127.0.0.1:8000/health" in compose


def test_server_dockerfile_installs_app_package() -> None:
    """Dockerfile должен устанавливать server package и стартовать API."""

    dockerfile = (REPO_ROOT / "server" / "Dockerfile").read_text(encoding="utf-8")

    assert "FROM python:3.12-slim" in dockerfile
    assert "COPY app ./app" in dockerfile
    assert "python -m pip install ." in dockerfile
    assert 'CMD ["python", "-m", "uvicorn"' in dockerfile


def test_nginx_preserves_api_prefix() -> None:
    """Nginx не должен срезать `/api` перед проксированием в FastAPI."""

    nginx_conf = (REPO_ROOT / "infra" / "nginx" / "nginx.conf").read_text(
        encoding="utf-8"
    )

    assert "location /api/" in nginx_conf
    assert "proxy_pass http://api:8000;" in nginx_conf
    assert "proxy_pass http://api:8000/;" not in nginx_conf
