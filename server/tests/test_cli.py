"""Тесты server CLI без подключения к реальной БД."""

from __future__ import annotations

from io import StringIO
from uuid import uuid4

from app import cli
from app.features.user_admin import CreatedUser, UsernameAlreadyExistsError


def test_parser_defaults_user_role_to_admin() -> None:
    """CLI по умолчанию создаёт admin-пользователя первого стенда."""

    parser = cli.build_parser()

    args = parser.parse_args(
        [
            "users",
            "create",
            "--username",
            "admin",
            "--password-stdin",
        ]
    )

    assert args.username == "admin"
    assert args.role == "admin"
    assert args.password_stdin is True


def test_main_reads_password_from_stdin_and_prints_success(monkeypatch) -> None:
    """`--password-stdin` удобен для VM/CI и не требует интерактивного prompt."""

    captured: dict[str, str] = {}

    def fake_create_user_in_database(*, session_factory, username, password, role):
        captured["username"] = username
        captured["password"] = password
        captured["role"] = role
        return CreatedUser(
            id=uuid4(),
            username=username,
            role=role,
            is_active=True,
        )

    monkeypatch.setattr(cli, "_create_user_in_database", fake_create_user_in_database)

    stdout = StringIO()
    stderr = StringIO()
    exit_code = cli.main(
        [
            "users",
            "create",
            "--username",
            "operator",
            "--role",
            "operator",
            "--password-stdin",
        ],
        stdin=StringIO("very-secure-password\n"),
        stdout=stdout,
        stderr=stderr,
        session_factory=lambda: None,
    )

    assert exit_code == 0
    assert captured == {
        "username": "operator",
        "password": "very-secure-password",
        "role": "operator",
    }
    assert "created user username=operator role=operator active=True" in stdout.getvalue()
    assert stderr.getvalue() == ""


def test_main_returns_usage_error_for_known_user_admin_error(monkeypatch) -> None:
    """Ожидаемые ошибки service-слоя дают exit code 2, а не traceback."""

    def fake_create_user_in_database(*, session_factory, username, password, role):
        raise UsernameAlreadyExistsError("user 'admin' already exists")

    monkeypatch.setattr(cli, "_create_user_in_database", fake_create_user_in_database)

    stdout = StringIO()
    stderr = StringIO()
    exit_code = cli.main(
        [
            "users",
            "create",
            "--username",
            "admin",
            "--password-stdin",
        ],
        stdin=StringIO("very-secure-password\n"),
        stdout=stdout,
        stderr=stderr,
        session_factory=lambda: None,
    )

    assert exit_code == 2
    assert stdout.getvalue() == ""
    assert "error: user 'admin' already exists" in stderr.getvalue()
