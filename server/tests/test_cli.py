"""Тесты server CLI без подключения к реальной БД."""

from __future__ import annotations

from io import StringIO
from uuid import uuid4

from app import cli
from app.features.pipeline_worker import PipelineWorkerCycleResult
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


def test_parser_accepts_pipeline_worker_run_once() -> None:
    """CLI должен иметь команду ручного запуска одного worker cycle."""

    parser = cli.build_parser()

    args = parser.parse_args(["pipeline-worker", "run-once"])

    assert args.resource == "pipeline-worker"
    assert args.action == "run-once"


def test_parser_accepts_pipeline_worker_run_with_max_cycles() -> None:
    """max-cycles нужен для ручной проверки long-running worker без вечного процесса."""

    parser = cli.build_parser()

    args = parser.parse_args(
        [
            "pipeline-worker",
            "run",
            "--max-cycles",
            "2",
            "--poll-interval-seconds",
            "0",
        ]
    )

    assert args.max_cycles == 2
    assert args.poll_interval_seconds == 0


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


def test_main_runs_pipeline_worker_once(monkeypatch) -> None:
    """run-once печатает итог одного worker cycle и возвращает 0."""

    def fake_run_once(*, session_factory):
        return PipelineWorkerCycleResult(
            claimed_run_id="01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
            status="succeeded",
            stuck_failed_count=1,
            message="/tmp/result_manifest.json",
        )

    monkeypatch.setattr(cli, "_run_pipeline_worker_once", fake_run_once)

    stdout = StringIO()
    stderr = StringIO()
    exit_code = cli.main(
        ["pipeline-worker", "run-once"],
        stdout=stdout,
        stderr=stderr,
        session_factory=lambda: None,
    )

    assert exit_code == 0
    assert "pipeline-worker status=succeeded" in stdout.getvalue()
    assert "claimed_run_id=01HX7M8M9RF2K0Z6GNZ6D7Q7AP" in stdout.getvalue()
    assert "stuck_failed_count=1" in stdout.getvalue()
    assert stderr.getvalue() == ""


def test_main_runs_pipeline_worker_loop_with_max_cycles(monkeypatch) -> None:
    """run --max-cycles позволяет проверить loop без зависания теста."""

    calls = 0

    def fake_run_once(*, session_factory):
        nonlocal calls
        calls += 1
        return PipelineWorkerCycleResult(
            claimed_run_id=None,
            status="idle",
        )

    monkeypatch.setattr(cli, "_run_pipeline_worker_once", fake_run_once)

    stdout = StringIO()
    stderr = StringIO()
    exit_code = cli.main(
        [
            "pipeline-worker",
            "run",
            "--max-cycles",
            "2",
            "--poll-interval-seconds",
            "0",
        ],
        stdout=stdout,
        stderr=stderr,
        session_factory=lambda: None,
    )

    assert exit_code == 0
    assert calls == 2
    assert stdout.getvalue().count("pipeline-worker status=idle") == 2
    assert stderr.getvalue() == ""
