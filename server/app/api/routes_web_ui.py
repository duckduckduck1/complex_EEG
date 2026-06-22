"""Server-rendered веб-кабинет (Jinja).

Страницы для сотрудников лаборатории: вход, список и карточка эксперимента.
Используют те же сервисы, что и JSON API; JSON API остаётся каноническим
контрактом, эти страницы — презентационный слой поверх него.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates

from app.api.deps_auth import get_auth_service
from app.api.routes_web_experiments import get_web_experiment_service
from app.core.config import settings
from app.features.auth import (
    AuthService,
    CurrentUser,
    InvalidCredentialsError,
    InvalidSessionError,
)
from app.features.web_experiments import (
    ExperimentListFilters,
    WebExperimentNotFoundError,
    WebExperimentService,
)


TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "web" / "templates"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

router = APIRouter(tags=["web-ui"], include_in_schema=False)


def _current_user_or_none(request: Request, auth_service: AuthService) -> CurrentUser | None:
    token = request.cookies.get(settings.session_cookie_name)
    try:
        return auth_service.authenticate_session_token(token)
    except InvalidSessionError:
        return None


def _redirect(target: str) -> RedirectResponse:
    return RedirectResponse(target, status_code=status.HTTP_303_SEE_OTHER)


def _set_session_cookie(response: RedirectResponse, *, token: str, expires_ts: int) -> None:
    response.set_cookie(
        key=settings.session_cookie_name,
        value=token,
        max_age=settings.session_ttl_hours * 60 * 60,
        expires=expires_ts,
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )


@router.get("/", response_class=HTMLResponse)
def index(
    request: Request,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> Response:
    if _current_user_or_none(request, auth_service) is None:
        return _redirect("/login")
    return _redirect("/experiments")


@router.get("/login", response_class=HTMLResponse)
def login_page(
    request: Request,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> Response:
    if _current_user_or_none(request, auth_service) is not None:
        return _redirect("/experiments")
    return templates.TemplateResponse(request, "login.html", {"error": None})


@router.post("/login", response_class=HTMLResponse)
def login_submit(
    request: Request,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
) -> Response:
    try:
        result = auth_service.login(username=username, password=password)
    except InvalidCredentialsError:
        return templates.TemplateResponse(
            request,
            "login.html",
            {"error": "Неверный логин или пароль"},
            status_code=status.HTTP_401_UNAUTHORIZED,
        )

    response = _redirect("/experiments")
    _set_session_cookie(response, token=result.session_token, expires_ts=int(result.expires_at.timestamp()))
    return response


@router.post("/logout")
def logout() -> RedirectResponse:
    response = _redirect("/login")
    response.delete_cookie(
        key=settings.session_cookie_name,
        path="/",
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
    )
    return response


@router.get("/experiments", response_class=HTMLResponse)
def experiments_page(
    request: Request,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    service: Annotated[WebExperimentService, Depends(get_web_experiment_service)],
) -> Response:
    user = _current_user_or_none(request, auth_service)
    if user is None:
        return _redirect("/login")

    page = service.list_experiments(
        ExperimentListFilters(
            status=None,
            date_from=None,
            date_to=None,
            search=None,
            limit=50,
            offset=0,
            sort="uploaded_at_desc",
        )
    )
    return templates.TemplateResponse(
        request,
        "experiments.html",
        {"user": user, "page": page},
    )


@router.get("/experiments/{experiment_id}", response_class=HTMLResponse)
def experiment_detail_page(
    request: Request,
    experiment_id: str,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    service: Annotated[WebExperimentService, Depends(get_web_experiment_service)],
) -> Response:
    user = _current_user_or_none(request, auth_service)
    if user is None:
        return _redirect("/login")

    try:
        detail = service.get_experiment_detail(experiment_id)
    except WebExperimentNotFoundError:
        return templates.TemplateResponse(
            request,
            "experiment_detail.html",
            {"user": user, "detail": None, "experiment_id": experiment_id},
            status_code=status.HTTP_404_NOT_FOUND,
        )

    return templates.TemplateResponse(
        request,
        "experiment_detail.html",
        {"user": user, "detail": detail, "experiment_id": experiment_id},
    )
