"""Service-слой для карточек экспериментов в Web UI.

Этот модуль даёт браузерному интерфейсу безопасное представление данных:
без server filesystem paths, MinIO object keys и других внутренних деталей.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Literal, Protocol

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db.models import (
    Experiment,
    ExperimentEvent,
    PipelineArtifact,
    PipelineRun,
    SourceFile,
)


ExperimentSort = Literal[
    "uploaded_at_desc",
    "uploaded_at_asc",
    "updated_at_desc",
    "display_name_asc",
    "status_asc",
]


@dataclass(frozen=True)
class ExperimentListFilters:
    """Фильтры таблицы экспериментов в Web UI."""

    status: str | None = None
    date_from: datetime | None = None
    date_to: datetime | None = None
    search: str | None = None
    limit: int = 50
    offset: int = 0
    sort: ExperimentSort = "uploaded_at_desc"


@dataclass(frozen=True)
class ExperimentErrorView:
    """Короткая ошибка для UI без stack trace и внутренних путей."""

    code: str
    message: str | None


@dataclass(frozen=True)
class ExperimentSummaryView:
    """Строка таблицы экспериментов."""

    experiment_id: str
    display_name: str
    status: str
    uploaded_at: datetime | None
    accepted_at: datetime | None
    updated_at: datetime
    last_pipeline_status: str | None
    last_error: ExperimentErrorView | None


@dataclass(frozen=True)
class ExperimentListPage:
    """Страница результата с offset pagination."""

    items: list[ExperimentSummaryView]
    total: int
    limit: int
    offset: int


@dataclass(frozen=True)
class SourceFileView:
    """Публичное описание исходного файла без bucket/object_key."""

    name: str
    size_bytes: int
    download_allowed: bool = False


@dataclass(frozen=True)
class ValidationView:
    """Состояние validation в карточке эксперимента."""

    status: str
    error: ExperimentErrorView | None


@dataclass(frozen=True)
class PipelineArtifactView:
    """Файл-результат pipeline, доступный через отдельный download endpoint."""

    artifact_id: str
    name: str
    kind: str
    size_bytes: int | None
    media_type: str | None


@dataclass(frozen=True)
class PipelineRunView:
    """Публичное описание запуска pipeline."""

    pipeline_run_id: str
    status: str
    trigger_type: str
    pipeline_version: str | None
    started_at: datetime | None
    finished_at: datetime | None
    error_code: str | None
    error_message: str | None
    artifacts: list[PipelineArtifactView] = field(default_factory=list)


@dataclass(frozen=True)
class ExperimentEventView:
    """Событие жизненного цикла эксперимента."""

    event_type: str
    from_status: str | None
    to_status: str | None
    message: str | None
    created_at: datetime


@dataclass(frozen=True)
class ExperimentDetailView:
    """Карточка эксперимента для Web UI."""

    experiment_id: str
    display_name: str
    status: str
    metadata: dict[str, object]
    uploaded_at: datetime | None
    accepted_at: datetime | None
    updated_at: datetime
    validation: ValidationView
    source_files: list[SourceFileView]
    pipeline_runs: list[PipelineRunView]
    events: list[ExperimentEventView]


class WebExperimentNotFoundError(ValueError):
    """Эксперимент не найден."""


class WebExperimentInvalidFilterError(ValueError):
    """Фильтры списка экспериментов противоречат друг другу."""


class WebExperimentRepository(Protocol):
    """Минимальный контракт чтения данных для Web UI."""

    def count_experiments(self, filters: ExperimentListFilters) -> int:
        """Возвращает total для текущего набора фильтров."""

    def list_experiments(self, filters: ExperimentListFilters) -> list[Experiment]:
        """Возвращает страницу экспериментов."""

    def get_experiment(self, experiment_id: str) -> Experiment | None:
        """Возвращает эксперимент по публичному experiment_id."""

    def get_latest_pipeline_status(self, experiment_id: str) -> str | None:
        """Возвращает статус последнего pipeline run."""

    def list_source_files(self, experiment_id: str) -> list[SourceFile]:
        """Возвращает исходные файлы эксперимента."""

    def list_pipeline_runs(self, experiment_id: str) -> list[PipelineRun]:
        """Возвращает запуски pipeline для эксперимента."""

    def list_pipeline_artifacts(self, pipeline_run_id: str) -> list[PipelineArtifact]:
        """Возвращает артефакты одного pipeline run."""

    def list_events(self, experiment_id: str) -> list[ExperimentEvent]:
        """Возвращает историю событий эксперимента."""


class SqlAlchemyWebExperimentRepository:
    """SQLAlchemy-репозиторий чтения экспериментов.

    На первом стенде объём данных лабораторный, поэтому отдельные запросы за
    latest pipeline status и artifacts допустимы. Если таблица вырастет, этот
    слой можно оптимизировать без изменения HTTP-контракта.
    """

    def __init__(self, db: Session) -> None:
        self._db = db

    def count_experiments(self, filters: ExperimentListFilters) -> int:
        statement = select(func.count(Experiment.id)).where(*_experiment_conditions(filters))
        return int(self._db.execute(statement).scalar_one())

    def list_experiments(self, filters: ExperimentListFilters) -> list[Experiment]:
        statement = (
            select(Experiment)
            .where(*_experiment_conditions(filters))
            .order_by(_sort_expression(filters.sort))
            .limit(filters.limit)
            .offset(filters.offset)
        )
        return list(self._db.execute(statement).scalars())

    def get_experiment(self, experiment_id: str) -> Experiment | None:
        statement = select(Experiment).where(Experiment.experiment_id == experiment_id)
        return self._db.execute(statement).scalars().first()

    def get_latest_pipeline_status(self, experiment_id: str) -> str | None:
        statement = (
            select(PipelineRun.status)
            .where(PipelineRun.experiment_id == experiment_id)
            .order_by(PipelineRun.created_at.desc())
            .limit(1)
        )
        return self._db.execute(statement).scalars().first()

    def list_source_files(self, experiment_id: str) -> list[SourceFile]:
        statement = (
            select(SourceFile)
            .where(SourceFile.experiment_id == experiment_id)
            .order_by(SourceFile.name.asc())
        )
        return list(self._db.execute(statement).scalars())

    def list_pipeline_runs(self, experiment_id: str) -> list[PipelineRun]:
        statement = (
            select(PipelineRun)
            .where(PipelineRun.experiment_id == experiment_id)
            .order_by(PipelineRun.created_at.desc())
        )
        return list(self._db.execute(statement).scalars())

    def list_pipeline_artifacts(self, pipeline_run_id: str) -> list[PipelineArtifact]:
        statement = (
            select(PipelineArtifact)
            .where(PipelineArtifact.pipeline_run_id == pipeline_run_id)
            .order_by(PipelineArtifact.created_at.asc())
        )
        return list(self._db.execute(statement).scalars())

    def list_events(self, experiment_id: str) -> list[ExperimentEvent]:
        statement = (
            select(ExperimentEvent)
            .where(ExperimentEvent.experiment_id == experiment_id)
            .order_by(ExperimentEvent.created_at.asc())
        )
        return list(self._db.execute(statement).scalars())


class WebExperimentService:
    """Use cases чтения экспериментов для Web UI."""

    def __init__(self, repository: WebExperimentRepository) -> None:
        self._repository = repository

    def list_experiments(self, filters: ExperimentListFilters) -> ExperimentListPage:
        """Возвращает страницу карточек экспериментов."""

        _validate_filters(filters)
        experiments = self._repository.list_experiments(filters)

        return ExperimentListPage(
            items=[self._summary(experiment) for experiment in experiments],
            total=self._repository.count_experiments(filters),
            limit=filters.limit,
            offset=filters.offset,
        )

    def get_experiment_detail(self, experiment_id: str) -> ExperimentDetailView:
        """Возвращает подробную карточку эксперимента."""

        experiment = self._repository.get_experiment(experiment_id)
        if experiment is None:
            raise WebExperimentNotFoundError("experiment was not found")

        return ExperimentDetailView(
            experiment_id=experiment.experiment_id,
            display_name=experiment.display_name,
            status=experiment.status,
            metadata=experiment.metadata_json or {},
            uploaded_at=experiment.uploaded_at,
            accepted_at=experiment.accepted_at,
            updated_at=experiment.updated_at,
            validation=_validation_view(experiment),
            source_files=[
                SourceFileView(
                    name=source_file.name,
                    size_bytes=source_file.size_bytes,
                    download_allowed=False,
                )
                for source_file in self._repository.list_source_files(experiment_id)
            ],
            pipeline_runs=[
                self._pipeline_run_view(pipeline_run)
                for pipeline_run in self._repository.list_pipeline_runs(experiment_id)
            ],
            events=[
                ExperimentEventView(
                    event_type=event.event_type,
                    from_status=event.from_status,
                    to_status=event.to_status,
                    message=event.message,
                    created_at=event.created_at,
                )
                for event in self._repository.list_events(experiment_id)
            ],
        )

    def _summary(self, experiment: Experiment) -> ExperimentSummaryView:
        return ExperimentSummaryView(
            experiment_id=experiment.experiment_id,
            display_name=experiment.display_name,
            status=experiment.status,
            uploaded_at=experiment.uploaded_at,
            accepted_at=experiment.accepted_at,
            updated_at=experiment.updated_at,
            last_pipeline_status=self._repository.get_latest_pipeline_status(
                experiment.experiment_id
            ),
            last_error=_last_error(experiment),
        )

    def _pipeline_run_view(self, pipeline_run: PipelineRun) -> PipelineRunView:
        return PipelineRunView(
            pipeline_run_id=pipeline_run.id,
            status=pipeline_run.status,
            trigger_type=pipeline_run.trigger_type,
            pipeline_version=pipeline_run.pipeline_version,
            started_at=pipeline_run.started_at,
            finished_at=pipeline_run.finished_at,
            error_code=pipeline_run.error_code,
            error_message=pipeline_run.error_message,
            artifacts=[
                PipelineArtifactView(
                    artifact_id=artifact.id,
                    name=artifact.name,
                    kind=artifact.kind,
                    size_bytes=artifact.size_bytes,
                    media_type=artifact.media_type,
                )
                for artifact in self._repository.list_pipeline_artifacts(pipeline_run.id)
            ],
        )


def _validate_filters(filters: ExperimentListFilters) -> None:
    if filters.date_from is not None and filters.date_to is not None:
        if filters.date_from > filters.date_to:
            raise WebExperimentInvalidFilterError("date_from must be before date_to")


def _experiment_conditions(filters: ExperimentListFilters) -> list[object]:
    conditions: list[object] = []

    if filters.status:
        conditions.append(Experiment.status == filters.status)

    if filters.date_from is not None:
        conditions.append(Experiment.uploaded_at >= filters.date_from)

    if filters.date_to is not None:
        conditions.append(Experiment.uploaded_at <= filters.date_to)

    if filters.search:
        pattern = f"%{filters.search}%"
        conditions.append(
            or_(
                Experiment.display_name.ilike(pattern),
                Experiment.experiment_id.ilike(pattern),
            )
        )

    return conditions


def _sort_expression(sort: ExperimentSort) -> object:
    sort_map = {
        "uploaded_at_desc": Experiment.uploaded_at.desc().nullslast(),
        "uploaded_at_asc": Experiment.uploaded_at.asc().nullslast(),
        "updated_at_desc": Experiment.updated_at.desc(),
        "display_name_asc": Experiment.display_name.asc(),
        "status_asc": Experiment.status.asc(),
    }
    return sort_map[sort]


def _validation_view(experiment: Experiment) -> ValidationView:
    if experiment.validation_error_code:
        return ValidationView(
            status="failed",
            error=ExperimentErrorView(
                code=experiment.validation_error_code,
                message=experiment.validation_error_message,
            ),
        )

    if experiment.accepted_at is not None:
        return ValidationView(status="accepted", error=None)

    return ValidationView(status="pending", error=None)


def _last_error(experiment: Experiment) -> ExperimentErrorView | None:
    if experiment.processing_error_code:
        return ExperimentErrorView(
            code=experiment.processing_error_code,
            message=experiment.processing_error_message,
        )

    if experiment.validation_error_code:
        return ExperimentErrorView(
            code=experiment.validation_error_code,
            message=experiment.validation_error_message,
        )

    return None
