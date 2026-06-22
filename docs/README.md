# Документация «Лаборатории Умного сна»

Карта документации. Доки живут в репозитории и ревьюятся через PR (docs-as-code).

## Начать отсюда

- [Видение и цели](vision.md) — что строим, цели и не-цели MVP, конечная цель,
  глоссарий.
- [Архитектурные решения (ADR)](decisions/) — зафиксированные решения, по одному
  на файл.
- [Правила работы над проектом](../CONTRIBUTING.md) — ветки, документация,
  коммиты, PR, единый стиль.

## Контракты (`reference/`)

- [Формат пакета эксперимента](reference/experiment_package.md) — контракт
  Flutter ↔ сервер.
- [HTTP API](reference/http_api.md) — серверные эндпоинты.

## Сервер (`server/`)

- [Обзор](server/README.md) ·
  [Веб-бэкенд и кабинет](server/web_backend.md) ·
  [Загрузка эксперимента](server/upload.md) ·
  [Валидация пакета](server/validation.md) ·
  [Пайплайн обработки](server/pipeline.md) ·
  [Хранение (MinIO + ссылки)](server/storage.md) ·
  [Хранилище данных (БД)](server/database.md) ·
  [Admin CLI](server/admin_cli.md)

## Flutter-приложение оператора (`flutter_app/`)

- [Обзор](flutter_app/README.md) ·
  [Архитектура](flutter_app/architecture.md) ·
  [Главный модуль](flutter_app/main_function.md) ·
  [Состояние (Bloc)](flutter_app/bloc.md) ·
  [BLE](flutter_app/ble.md) ·
  [Запись сигнала](flutter_app/recording.md) ·
  [Разметка](flutter_app/annotation.md) ·
  [Восстановление](flutter_app/recovery.md) ·
  [Визуализация](flutter_app/visualization.md) ·
  [Синхронизация с сервером](flutter_app/server_sync.md) ·
  [Взаимодействие с сервером (обзор)](flutter_app/server_app.md) ·
  [Локальное хранение](flutter_app/storage.md) ·
  [Настройки](flutter_app/settings.md) ·
  [Эксперименты](flutter_app/experiments.md) ·
  [Тестирование](flutter_app/testing.md) ·
  [Утилиты](flutter_app/utils.md)

## Инфраструктура (`infra/`)

- [Обзор](infra/README.md) ·
  [Linux](infra/linux.md) ·
  [Docker](infra/docker.md) ·
  [Ansible](infra/ansible.md) ·
  [CI/CD](infra/ci_cd.md) ·
  [Мониторинг](infra/monitoring.md) ·
  [Бэкапы](infra/backup.md) ·
  [Runbook](infra/runbook.md)

## Ресурсы

- `diagrams/` — схемы архитектуры (`infra_architecture.svg`, `scheme_complex.png`).
- `manuals/` — даташиты железа (АЦП `max30003.pdf`).

## Зоны ответственности

- **Richard (`duckduckduck1`)** — сервер, веб, Flutter.
- **MURRyao** — слой БД ([server/database.md](server/database.md), схема в
  `scripts/db_scripts/`) и MinIO storage.
