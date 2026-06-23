"""Server-rendered веб-кабинет (Jinja).

Страницы для сотрудников лаборатории: вход, список и карточка эксперимента.
Используют те же сервисы, что и JSON API; JSON API остаётся каноническим
контрактом, эти страницы — презентационный слой поверх него.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, Form, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates

from app.api.deps_auth import build_csrf_token, get_auth_service
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
from app.features.upload.session_service import DEFAULT_UPLOAD_FILES


TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "web" / "templates"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

router = APIRouter(tags=["web-ui"], include_in_schema=False)
UPLOAD_OPERATOR_ROLES = frozenset({"operator", "admin"})
REQUIRED_UPLOAD_FILES = ("signal.bin", "experiment.json")

EXPERIMENTS_PAGE_SIZE = 20
SORT_OPTIONS = (
    ("uploaded_at_desc", "Сначала новые"),
    ("uploaded_at_asc", "Сначала старые"),
    ("updated_at_desc", "По обновлению"),
    ("display_name_asc", "По названию"),
    ("status_asc", "По статусу"),
)
_SORT_VALUES = frozenset(value for value, _ in SORT_OPTIONS)
STATUS_OPTIONS = (
    ("", "Все статусы"),
    ("uploading", "uploading"),
    ("accepted", "accepted"),
    ("validation_failed", "validation_failed"),
    ("processing", "processing"),
    ("processed", "processed"),
    ("processing_failed", "processing_failed"),
)


def _can_upload(user: CurrentUser) -> bool:
    return user.role in UPLOAD_OPERATOR_ROLES


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
    status_filter: Annotated[str, Query(alias="status", max_length=64)] = "",
    search: Annotated[str, Query(max_length=128)] = "",
    sort: Annotated[str, Query(max_length=32)] = "uploaded_at_desc",
    page_number: Annotated[int, Query(alias="page", ge=1)] = 1,
) -> Response:
    user = _current_user_or_none(request, auth_service)
    if user is None:
        return _redirect("/login")

    status_value = status_filter.strip() or None
    search_value = search.strip() or None
    sort_value = sort if sort in _SORT_VALUES else "uploaded_at_desc"
    offset = (page_number - 1) * EXPERIMENTS_PAGE_SIZE

    page = service.list_experiments(
        ExperimentListFilters(
            status=status_value,
            search=search_value,
            limit=EXPERIMENTS_PAGE_SIZE,
            offset=offset,
            sort=sort_value,
        )
    )

    base_params: dict[str, str] = {}
    if status_value:
        base_params["status"] = status_value
    if search_value:
        base_params["search"] = search_value
    if sort_value != "uploaded_at_desc":
        base_params["sort"] = sort_value

    def _page_url(number: int) -> str:
        return "/experiments?" + urlencode({**base_params, "page": number})

    has_next = (page.offset + page.limit) < page.total

    return templates.TemplateResponse(
        request,
        "experiments.html",
        {
            "user": user,
            "page": page,
            "can_upload": _can_upload(user),
            "status_options": STATUS_OPTIONS,
            "sort_options": SORT_OPTIONS,
            "current_status": status_value or "",
            "current_search": search_value or "",
            "current_sort": sort_value,
            "has_filters": bool(status_value or search_value),
            "shown_from": page.offset + 1 if page.total else 0,
            "shown_to": min(page.offset + page.limit, page.total),
            "prev_url": _page_url(page_number - 1) if page_number > 1 else None,
            "next_url": _page_url(page_number + 1) if has_next else None,
        },
    )


@router.get("/uploads/new", response_class=HTMLResponse)
def upload_page(
    request: Request,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> Response:
    user = _current_user_or_none(request, auth_service)
    if user is None:
        return _redirect("/login")

    can_upload = _can_upload(user)
    session_token = request.cookies.get(settings.session_cookie_name)
    return templates.TemplateResponse(
        request,
        "upload.html",
        {
            "user": user,
            "can_upload": can_upload,
            "upload_files": sorted(DEFAULT_UPLOAD_FILES),
            "required_upload_files": REQUIRED_UPLOAD_FILES,
            "csrf_token": build_csrf_token(session_token) if session_token else "",
        },
        status_code=status.HTTP_200_OK if can_upload else status.HTTP_403_FORBIDDEN,
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
            {
                "user": user,
                "detail": None,
                "experiment_id": experiment_id,
                "can_upload": _can_upload(user),
            },
            status_code=status.HTTP_404_NOT_FOUND,
        )

    return templates.TemplateResponse(
        request,
        "experiment_detail.html",
        {
            "user": user,
            "detail": detail,
            "experiment_id": experiment_id,
            "can_upload": _can_upload(user),
        },
    )
