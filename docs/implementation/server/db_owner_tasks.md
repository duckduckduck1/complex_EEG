# DB owner tasks

## Статус

Рабочий документ для владельца слоя БД.

Документ фиксирует, что именно нужно сделать в DB-ветке, какие границы MVP нельзя
расширять и по каким правилам мы будем ревьюить изменения.

---

## Рабочая ветка

Для работы с БД используется отдельная ветка:

```bash
feature/eeg-db-owner-workspace
```

Базовая ветка:

```bash
dev
```

Перед созданием ветки нужно обновить локальную `dev`:

```bash
git switch dev
git pull origin dev
git switch -c feature/eeg-db-owner-workspace
```

Все изменения по БД идут через pull request в `dev`.

---

## Цель ветки

Довести слой БД до состояния, в котором остальные части сервера смогут спокойно
опираться на стабильные таблицы, SQLAlchemy-модели и Alembic-миграции.

Текущий продукт - EEG-only MVP.

Flutter-приложение формирует локальный пакет эксперимента:

```text
{experiment_folder}/
  signal.bin
  experiment.json
  journal.ndjson optional
  app.log optional
```

Web UI загружает этот пакет на сервер. Сервер валидирует пакет, сохраняет
метаданные в PostgreSQL, а сами файлы хранит в файловой системе.

---

## Граница MVP

В MVP входит:

- пользователь web UI;
- ручная загрузка EEG-эксперимента через web UI;
- проверка уникальности `experiment_id`;
- хранение метаданных эксперимента;
- хранение статусов upload, validation и pipeline;
- история событий по эксперименту;
- audit-события web UI;
- Alembic-миграции;
- индексы и ограничения, нужные для текущих серверных flow.

В MVP не входит:

- microscopy;
- LAS/LAZ;
- MinIO/S3;
- Airflow;
- lakehouse layers;
- универсальный каталог всех лабораторных файлов;
- обработка изображений;
- отдельная data platform поверх текущего сервиса.

Эти идеи можно сохранить как будущий отдельный проект или отдельный ADR, но не
добавлять в текущую БД без нового архитектурного решения.

---

## Контракт хранения

PostgreSQL хранит:

- пользователей;
- карточки экспериментов;
- upload sessions;
- список исходных файлов;
- validation errors;
- pipeline runs;
- pipeline artifacts;
- experiment events;
- audit events.

Файловая система хранит:

- `signal.bin`;
- `experiment.json`;
- `journal.ndjson`;
- `app.log`;
- validation reports;
- pipeline logs;
- pipeline artifacts.

PostgreSQL не хранит бинарный EEG-сигнал.

---

## Таблицы публичного контракта

Остальные части сервера могут опираться на эти сущности:

```text
users
experiments
upload_sessions
source_files
experiment_events
pipeline_runs
pipeline_artifacts
audit_events
```

Если DB owner хочет удалить или переименовать одну из этих таблиц, сначала нужно
обновить документацию и согласовать изменение в PR.

---

## Главные поля контракта

### `experiments.experiment_id`

Внешний стабильный идентификатор EEG-эксперимента.

Правило формата:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Должен быть уникальным на сервере.

Именно это поле защищает сервер от дублей и path traversal.

### `experiments.display_name`

Человекочитаемое название эксперимента.

Может повторяться, если DB owner не предложит и не обоснует scoped uniqueness.

### `experiments.metadata_json`

Хранит поле `metadata` из `experiment.json` как есть.

Полный `experiment.json` остаётся в файловом хранилище.

### `source_files.relative_path`

Путь относительно директории `source/`.

Абсолютные filesystem paths не должны возвращаться в API.

### `pipeline_artifacts.relative_path`

Путь относительно директории конкретного pipeline run.

Абсолютные filesystem paths не должны возвращаться в API.

---

## Что DB owner может менять

DB owner может менять:

- SQLAlchemy-модели;
- Alembic-миграции;
- индексы;
- foreign keys;
- constraints;
- nullable flags;
- enum-подобные ограничения;
- структуру ownership-полей;
- структуру audit events;
- тесты DB-моделей;
- repository/query слой, когда он появится.

DB owner может предлагать изменения в документации:

- `docs/implementation/server/storage.md`;
- `docs/implementation/server/upload.md`;
- `docs/implementation/server/web_backend.md`;
- `docs/implementation/server/api.md`.

Но такие изменения должны быть связаны с текущим EEG MVP.

---

## Что DB owner не должен менять в этой ветке

В этой ветке не нужно:

- переписывать весь сервер;
- менять Flutter-документацию без необходимости;
- добавлять новые продуктовые домены;
- добавлять S3/MinIO;
- добавлять Airflow;
- добавлять универсальную модель файлов для всех будущих лабораторных данных;
- менять upload flow с Web UI обратно на прямой Flutter upload;
- заменять Alembic raw SQL-скриптами как главным источником схемы.

Источник схемы:

```text
SQLAlchemy models -> Alembic migrations -> PostgreSQL
```

---

## Задачи

### 1. Проверить текущие SQLAlchemy-модели

Файл:

```text
server/app/db/models.py
```

Нужно сверить модели с:

```text
docs/implementation/server/storage.md
docs/implementation/server/upload.md
docs/implementation/server/web_backend.md
docs/implementation/server/api.md
```

Результат:

- модели соответствуют документации;
- расхождения либо исправлены в коде, либо явно описаны в PR.

---

### 2. Спроектировать ownership экспериментов

Нужно решить, как пользователь web UI связан с экспериментом.

Минимальные вопросы:

1. Кто загрузил эксперимент?
2. Кто является владельцем эксперимента?
3. Кто может видеть эксперимент в web UI?
4. Нужно ли разделять `uploaded_by_user_id` и `owner_user_id`?
5. Нужно ли поле `created_by_user_id` для будущих сценариев?

Минимальное ожидаемое решение для MVP:

```text
experiments.uploaded_by_user_id -> users.id
experiments.owner_user_id -> users.id
upload_sessions.created_by_user_id -> users.id
```

Если DB owner считает, что для MVP достаточно меньшего набора полей, это нужно
объяснить в PR.

---

### 3. Проверить уникальность `experiment_id`

Нужно подтвердить и реализовать правило:

```text
experiments.experiment_id unique not null
```

Дополнительно проверить:

- длина не больше 64 символов;
- формат проверяется на уровне server validation;
- БД защищает от дубля даже при race condition.

БД не обязана проверять regex-формат, если это уже делает API/validator, но
unique constraint обязателен.

---

### 4. Уточнить enum-подобные статусы

Нужно проверить, какие статусы реально используются в документации:

```text
upload_sessions.status
experiments.status
pipeline_runs.status
```

Для MVP можно оставить `text/string` поля, но DB owner должен решить:

- оставляем свободный text и валидируем на уровне Python;
- добавляем PostgreSQL enum;
- добавляем CHECK constraints.

Рекомендуемый вариант для первого стенда:

```text
String + Python constants + tests
```

Причина: статусы ещё могут немного меняться во время реализации.

---

### 5. Добавить foreign keys там, где они безопасны

Нужно рассмотреть связи:

```text
source_files.experiment_id -> experiments.experiment_id
experiment_events.experiment_id -> experiments.experiment_id
pipeline_runs.experiment_id -> experiments.experiment_id
pipeline_artifacts.pipeline_run_id -> pipeline_runs.id
pipeline_artifacts.experiment_id -> experiments.experiment_id
audit_events.actor_user_id -> users.id
```

Если связь не добавляется, нужно объяснить почему.

Например, иногда `experiment_events` можно оставить append-only без жёсткой FK,
но это должно быть осознанное решение.

---

### 6. Создать первую реальную Alembic migration

Нужно создать migration, которая создаёт текущие таблицы.

Команда:

```bash
cd server
alembic revision --autogenerate -m "create initial eeg schema"
```

После генерации migration нельзя просто доверять autogenerate.

Нужно вручную проверить:

- имена таблиц;
- типы колонок;
- nullable;
- indexes;
- unique constraints;
- foreign keys;
- downgrade.

---

### 7. Проверить migration lifecycle

Минимальная проверка:

```bash
cd server
pytest
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

Если проверка идёт против локального PostgreSQL в Docker, нужно указать это в PR.

Если проверка идёт только на SQLite/без реальной БД, это тоже нужно честно указать.

---

### 8. Добавить DB tests

Минимальные тесты:

- модели импортируются;
- metadata содержит все таблицы;
- `experiment_id` уникален;
- `username` уникален;
- индексы существуют на ключевых полях;
- Alembic видит metadata;
- migration upgrade/downgrade проверены вручную или автоматизированы.

Если тест требует PostgreSQL, но в CI PostgreSQL ещё не поднят, можно пока
оставить unit-level тест и описать gap в PR.

---

## Что написать в PR

В PR нужно явно ответить:

1. Какие таблицы изменены?
2. Какие constraints добавлены?
3. Какие indexes добавлены?
4. Как теперь хранится ownership эксперимента?
5. Как проверялась migration?
6. Какие решения оставлены на будущий этап?
7. Какие документы обновлены?

---

## Review checklist

Перед отправкой PR проверить:

- проект всё ещё EEG-only;
- нет MinIO/S3/Airflow/lakehouse/microscopy;
- нет хранения `signal.bin` в PostgreSQL;
- нет абсолютных filesystem paths в API-контракте;
- `experiment_id` уникален;
- ownership пользователя явно определён;
- Alembic migration обратима там, где это разумно;
- `pytest` проходит;
- документация и модели не противоречат друг другу.

---

## Как ревьюить эту ветку

Ревью должно идти не по принципу "нравится/не нравится", а по контракту.

Главные вопросы ревью:

1. Помогает ли изменение текущему EEG MVP?
2. Используется ли оно upload, validation, web UI или pipeline flow?
3. Можно ли это пока хранить в `metadata_json`, не создавая новую таблицу?
4. Не добавляет ли изменение новый продуктовый домен?
5. Не усложняет ли оно реализацию без пользы для первого стенда?

Если изменение полезное, но относится к будущей большой платформе, его лучше
вынести в отдельный ADR или issue, а не добавлять в MVP.

---

## Ветка `feat/added-db-implementation`

Ветку `feat/added-db-implementation` не нужно мержить в текущий `dev`.

Причина:

- она полезна как черновик будущей data platform;
- она расширяет bounded context проекта;
- она добавляет сущности вне EEG MVP;
- она конфликтует с текущей документацией и реализационным планом.

Из неё можно забирать отдельные идеи, но только через маленькие EEG-specific PR.

---

## Сообщение для DB owner

Можно отправить так:

```text
Мы выделили для тебя отдельную ветку feature/eeg-db-owner-workspace.

Твоя зона ответственности - PostgreSQL, SQLAlchemy models, Alembic migrations,
constraints, indexes, ownership экспериментов и DB tests.

Просьба держать текущий scope: только EEG MVP. Не добавляем microscopy, MinIO,
Airflow, lakehouse и универсальную платформу файлов. Эти идеи не теряем, но
оставляем на будущий отдельный этап.

Главный документ для работы:
docs/implementation/server/db_owner_tasks.md

PR открываем в dev. В описании PR нужно объяснить каждое schema decision:
что изменено, зачем это нужно текущему EEG flow и как проверялись миграции.
```
