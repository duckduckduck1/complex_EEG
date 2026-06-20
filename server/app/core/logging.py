"""Настройка логирования server-приложения.

В Docker-приложениях основной поток логов должен идти в stdout/stderr.
Контейнерная платформа уже умеет собирать этот поток через `docker compose logs`,
а позже его можно подключить к централизованному логированию.
"""

from __future__ import annotations

import json
import logging
import re
import time
from collections.abc import Awaitable, Callable
from uuid import uuid4

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


REQUEST_LOGGER_NAME = "complex_eeg.request"
REQUEST_ID_PATTERN = re.compile(r"^[a-zA-Z0-9._:-]{1,128}$")


def configure_logging(log_level: str) -> None:
    """Настраивает базовый формат логов приложения.

    Формат `%(message)s` выбран намеренно: structured events уже сериализуются в
    JSON строку, и лишние префиксы logging formatter'а мешали бы парсингу.
    """

    level = _parse_log_level(log_level)
    logging.basicConfig(level=level, format="%(message)s")
    logging.getLogger().setLevel(level)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Пишет structured log на каждый HTTP-запрос."""

    def __init__(
        self,
        app,
        *,
        request_id_header: str,
        logger_name: str = REQUEST_LOGGER_NAME,
    ) -> None:
        super().__init__(app)
        self._request_id_header = request_id_header
        self._logger = logging.getLogger(logger_name)

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = _get_or_create_request_id(
            request.headers.get(self._request_id_header)
        )
        started_at = time.perf_counter()
        status_code = 500
        error_type: str | None = None
        response: Response | None = None

        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        except Exception as exc:
            error_type = exc.__class__.__name__
            raise
        finally:
            duration_ms = round((time.perf_counter() - started_at) * 1000, 2)

            if response is not None:
                response.headers[self._request_id_header] = request_id

            self._logger.info(
                _json_log_line(
                    event="http_request",
                    request_id=request_id,
                    method=request.method,
                    path=request.url.path,
                    status_code=status_code,
                    duration_ms=duration_ms,
                    client_ip=_client_ip(request),
                    user_agent=request.headers.get("user-agent"),
                    error_type=error_type,
                )
            )


def _parse_log_level(log_level: str) -> int:
    level = logging.getLevelName(log_level.upper())
    if isinstance(level, int):
        return level

    return logging.INFO


def _get_or_create_request_id(incoming_request_id: str | None) -> str:
    if incoming_request_id and REQUEST_ID_PATTERN.fullmatch(incoming_request_id):
        return incoming_request_id

    return uuid4().hex


def _client_ip(request: Request) -> str | None:
    if request.client is None:
        return None

    return request.client.host


def _json_log_line(**fields: object) -> str:
    payload = {
        key: value
        for key, value in fields.items()
        if value is not None
    }
    return json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
