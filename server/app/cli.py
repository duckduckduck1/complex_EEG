"""CLI для служебного управления server-приложением.

Запуск:

    python -m app.cli users create --username admin --role admin

После editable install также доступна console command:

    complex-eeg users create --username admin --role admin
"""

from __future__ import annotations

import argparse
import getpass
import sys
import time
from collections.abc import Callable, Sequence
from typing import TextIO

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import SessionLocal
from app.features.pipeline_worker import (
    PipelineWorkerCycleResult,
    PipelineWorkerService,
    SqlAlchemyPipelineWorkerRepository,
)
from app.features.user_admin import (
    ALLOWED_USER_ROLES,
    CreatedUser,
    SqlAlchemyUserAdminRepository,
    UserAdminError,
    UserAdminService,
)


SessionFactory = Callable[[], Session]


class CliUsageError(ValueError):
    """Ошибка пользовательского ввода на уровне CLI."""


def build_parser() -> argparse.ArgumentParser:
    """Собирает argparse parser без побочных эффектов.

    Отдельная функция удобна для тестов: можно проверить CLI-контракт, не
    подключаясь к PostgreSQL и не запуская приложение.
    """

    parser = argparse.ArgumentParser(prog="complex-eeg")
    subparsers = parser.add_subparsers(dest="resource", required=True)

    users_parser = subparsers.add_parser("users", help="manage Web UI users")
    users_subparsers = users_parser.add_subparsers(dest="action", required=True)

    create_parser = users_subparsers.add_parser(
        "create",
        help="create an active Web UI user",
    )
    create_parser.add_argument("--username", required=True)
    create_parser.add_argument(
        "--role",
        choices=sorted(ALLOWED_USER_ROLES),
        default="admin",
    )
    create_parser.add_argument(
        "--password-stdin",
        action="store_true",
        help="read password from stdin instead of interactive prompt",
    )
    create_parser.set_defaults(handler=_handle_users_create)

    worker_parser = subparsers.add_parser(
        "pipeline-worker",
        help="run background pipeline worker",
    )
    worker_subparsers = worker_parser.add_subparsers(dest="action", required=True)

    run_once_parser = worker_subparsers.add_parser(
        "run-once",
        help="process one queued pipeline run and exit",
    )
    run_once_parser.set_defaults(handler=_handle_pipeline_worker_run_once)

    run_parser = worker_subparsers.add_parser(
        "run",
        help="poll PostgreSQL and process pipeline runs forever",
    )
    run_parser.add_argument(
        "--max-cycles",
        type=int,
        default=None,
        help="stop after N cycles; useful for manual checks",
    )
    run_parser.add_argument(
        "--poll-interval-seconds",
        type=float,
        default=None,
        help="override PIPELINE_POLL_INTERVAL_SECONDS",
    )
    run_parser.set_defaults(handler=_handle_pipeline_worker_run)

    return parser


def main(
    argv: Sequence[str] | None = None,
    *,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    session_factory: SessionFactory = SessionLocal,
) -> int:
    """Точка входа CLI.

    Возвращаем int вместо прямого `sys.exit`, чтобы CLI было проще тестировать.
    В блоке `if __name__ == "__main__"` этот код превращается в exit code.
    """

    actual_stdin = stdin or sys.stdin
    actual_stdout = stdout or sys.stdout
    actual_stderr = stderr or sys.stderr

    parser = build_parser()
    args = parser.parse_args(argv)

    return args.handler(
        args,
        stdin=actual_stdin,
        stdout=actual_stdout,
        stderr=actual_stderr,
        session_factory=session_factory,
    )


def _handle_users_create(
    args: argparse.Namespace,
    *,
    stdin: TextIO,
    stdout: TextIO,
    stderr: TextIO,
    session_factory: SessionFactory,
) -> int:
    try:
        password = _read_password(args, stdin=stdin)
        user = _create_user_in_database(
            session_factory=session_factory,
            username=args.username,
            password=password,
            role=args.role,
        )
    except (CliUsageError, UserAdminError) as exc:
        print(f"error: {exc}", file=stderr)
        return 2
    except SQLAlchemyError as exc:
        print(f"database error: {exc}", file=stderr)
        return 1

    print(
        f"created user username={user.username} role={user.role} active={user.is_active}",
        file=stdout,
    )
    return 0


def _handle_pipeline_worker_run_once(
    args: argparse.Namespace,
    *,
    stdin: TextIO,
    stdout: TextIO,
    stderr: TextIO,
    session_factory: SessionFactory,
) -> int:
    try:
        result = _run_pipeline_worker_once(session_factory=session_factory)
    except SQLAlchemyError as exc:
        print(f"database error: {exc}", file=stderr)
        return 1

    _print_worker_result(result, stdout=stdout)
    return 0


def _handle_pipeline_worker_run(
    args: argparse.Namespace,
    *,
    stdin: TextIO,
    stdout: TextIO,
    stderr: TextIO,
    session_factory: SessionFactory,
) -> int:
    poll_interval = (
        settings.pipeline_poll_interval_seconds
        if args.poll_interval_seconds is None
        else args.poll_interval_seconds
    )
    cycles_completed = 0

    while True:
        try:
            result = _run_pipeline_worker_once(session_factory=session_factory)
        except SQLAlchemyError as exc:
            print(f"database error: {exc}", file=stderr)
            return 1

        _print_worker_result(result, stdout=stdout)
        cycles_completed += 1

        if args.max_cycles is not None and cycles_completed >= args.max_cycles:
            return 0

        time.sleep(poll_interval)


def _read_password(args: argparse.Namespace, *, stdin: TextIO) -> str:
    if args.password_stdin:
        # strip убирает перевод строки, который добавляет shell pipeline.
        return stdin.read().strip()

    first_password = getpass.getpass("Password: ")
    second_password = getpass.getpass("Repeat password: ")

    if first_password != second_password:
        raise CliUsageError("passwords do not match")

    return first_password


def _create_user_in_database(
    *,
    session_factory: SessionFactory,
    username: str,
    password: str,
    role: str,
) -> CreatedUser:
    with session_factory() as db:
        repository = SqlAlchemyUserAdminRepository(db)
        service = UserAdminService(repository)

        try:
            user = service.create_user(
                username=username,
                password=password,
                role=role,
            )
            db.commit()
        except Exception:
            db.rollback()
            raise

        return user


def _run_pipeline_worker_once(
    *,
    session_factory: SessionFactory,
) -> PipelineWorkerCycleResult:
    with session_factory() as db:
        service = PipelineWorkerService(
            repository=SqlAlchemyPipelineWorkerRepository(db),
            pipeline_results_root=settings.pipeline_results_dir,
            stuck_heartbeat_minutes=settings.pipeline_stuck_heartbeat_minutes,
            max_run_duration_hours=settings.pipeline_max_run_duration_hours,
        )
        return service.run_once()


def _print_worker_result(result: PipelineWorkerCycleResult, *, stdout: TextIO) -> None:
    claimed = result.claimed_run_id or "-"
    message = f" message={result.message}" if result.message else ""
    print(
        "pipeline-worker "
        f"status={result.status} "
        f"claimed_run_id={claimed} "
        f"stuck_failed_count={result.stuck_failed_count}"
        f"{message}",
        file=stdout,
    )


if __name__ == "__main__":
    raise SystemExit(main())
