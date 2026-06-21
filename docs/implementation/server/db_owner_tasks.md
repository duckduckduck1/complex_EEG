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
опираться на стабильные таблицы, SQLAlchemy-модели и SQL init scripts.

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
метаданные в PostgreSQL, а сами файлы после `accepted` хранит в MinIO bronze.

См. [ADR 0002](../../decisions/0002-eeg-minio-bronze-storage.md).

---

## Граница MVP

В MVP входит:

- пользователь web UI;
- ручная загрузка EEG-эксперимента через web UI;
- проверка уникальности `experiment_id`;
- хранение метаданных эксперимента;
- MinIO bronze для source-файлов;
- ACID-boundary upload flow: MinIO upload before accepted DB commit;
- SQL init scripts и Docker init для PostgreSQL/MinIO;
- хранение статусов upload, validation и pipeline;
- история событий по эксперименту;
- журнал upload storage boundary и orphan MinIO objects;
- audit-события web UI;
- индексы и ограничения, нужные для текущих server flow.

В MVP не входит:

- microscopy;
- LAS/LAZ;
- Airflow;
- silver/gold pipeline outputs в MinIO (buckets создаются, схема — позже);
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
- upload storage events;
- orphan object records for failed accepted commits;
- список исходных файлов с `bucket` + `object_key`;
- validation errors;
- pipeline runs;
- pipeline artifacts;
- experiment events;
- audit events;

MinIO bronze хранит immutable source-пакет после `accepted`. Accepted metadata
появляется в PostgreSQL только после успешного upload в MinIO и проверки
читаемости объектов.

Локальная файловая система — staging/cache (`upload_tmp`), validation reports и
pipeline results. Локальная `experiments/{experiment_id}/source/` удаляется
после successful MinIO upload и PostgreSQL commit.

PostgreSQL не хранит бинарный EEG-сигнал.

---

## Таблицы публичного контракта

Остальные части сервера могут опираться на эти сущности:

```text
users
experiments
upload_sessions
upload_storage_events
upload_orphan_objects
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

Полный `experiment.json` остаётся в MinIO bronze как исходный объект.

### `experiments.storage_bucket` / `experiments.storage_prefix`

После `accepted` указывают на bucket и prefix source-пакета, например:

```text
storage_bucket = lakehouse-bronze
storage_prefix = eeg/{experiment_id}/
```

### `source_files.relative_path`

Имя файла внутри `storage_prefix`, например `signal.bin` или
`experiment.json`.

Абсолютные filesystem paths не должны возвращаться в API.

### `source_files.bucket` / `source_files.object_key`

Полная ссылка на объект в MinIO. Пара `(bucket, object_key)` уникальна и
используется как дополнительная защита от дублей объектов.

### `upload_sessions.experiment_id` для active sessions

Для active statuses:

```text
created
uploading
completed
validating
```

должен существовать partial unique index:

```text
unique upload_sessions(experiment_id) where status is active
```

Он закрывает race condition, когда два API-процесса одновременно создают upload
session для одного `experiment_id`.

### `upload_storage_events`

Журнал событий связки upload session с MinIO object storage. Для accepted upload
пишется в той же PostgreSQL transaction, что и `experiments`, `source_files`,
`pipeline_runs` и `experiment_events`.

Минимальные события:

```text
minio_object_uploaded
source_package_accepted
```

### `upload_orphan_objects`

Best-effort журнал MinIO objects, загруженных до failed PostgreSQL commit. Если
accepted DB transaction откатилась после успешного MinIO upload, эти объекты
получают статус:

```text
pending_cleanup
```

Таблица нужна для cleanup/manual audit.

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
- добавлять Airflow;
- мержить полную lakehouse-схему из `feat/added-db-implementation`;
- добавлять универсальную модель файлов для всех будущих лабораторных данных;
- менять upload flow с Web UI обратно на прямой Flutter upload;
- расходиться между `scripts/db_scripts/010_schema.sql`, ORM-моделями и
  документацией контракта.

Источник схемы первого стенда:

```text
scripts/db_scripts/010_schema.sql -> PostgreSQL
server/app/db/models.py           -> ORM mirror
scripts/minio/010_init_buckets.sh -> MinIO buckets
```

Incremental changes после первого стенда могут идти через Alembic migration files.

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

Нужно также подтвердить DB-level защиту active upload sessions:

```text
upload_sessions(experiment_id) unique where status in active statuses
```

Application-level precheck недостаточен, потому что два API-процесса могут
одновременно пройти `find_active_session_by_experiment_id`.

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
upload_storage_events.upload_session_id -> upload_sessions.id
upload_orphan_objects.upload_session_id -> upload_sessions.id
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

### 6. Поддерживать SQL init scripts как source of truth

Исполняемая схема первого стенда:

```text
scripts/db_scripts/010_schema.sql
scripts/db_scripts/090_seed_dev.sql
scripts/minio/010_init_buckets.sh
```

После изменения SQL нужно синхронизировать:

- `server/app/db/models.py`;
- `docs/implementation/server/storage.md`;
- `server/tests/test_db_models.py`;
- `server/tests/test_db_schema_scripts.py`.

Alembic migration для initial schema не используется. Incremental migrations
можно добавить позже отдельным PR.

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
- partial unique index active upload session существует;
- таблицы `upload_storage_events` и `upload_orphan_objects` есть в ORM и SQL;
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
4. Как закрываются race conditions upload flow?
5. Как логируются orphan MinIO objects после failed DB commit?
6. Как теперь хранится ownership эксперимента?
7. Как проверялась migration?
8. Какие решения оставлены на будущий этап?
9. Какие документы обновлены?

---

## Review checklist

Перед отправкой PR проверить:

- проект всё ещё EEG-only;
- нет Airflow / microscopy / universal lakehouse catalog;
- accepted source-файлы ссылаются на MinIO bronze;
- `experiment_id` уникален;
- две active upload sessions для одного `experiment_id` запрещены на уровне БД;
- `complete` использует row-level lock upload session;
- `source_files (bucket, object_key)` уникален;
- orphan MinIO objects после failed DB commit имеют стратегию cleanup/audit;
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

Просьба держать текущий scope: только EEG MVP. MinIO bronze и SQL init scripts
входят в scope (ADR 0002). Не добавляем microscopy, Airflow и universal
lakehouse platform.

Главный документ для работы:
docs/implementation/server/db_owner_tasks.md

PR открываем в dev. В описании PR нужно объяснить каждое schema decision:
что изменено, зачем это нужно текущему EEG flow и как проверялись миграции.
```
