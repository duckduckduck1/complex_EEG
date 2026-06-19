# storage.md

## Статус

Draft.

Документ описывает реализацию хранилища серверной части: PostgreSQL, файловые
пути, миграции и правила консистентности между БД и файловой системой.

---

## Решение

Используются два слоя хранения:

1. PostgreSQL — метаданные, статусы, события, ссылки на файлы и результаты.
2. Файловая система — `signal.bin`, `experiment.json`, логи и производные
   результаты.

PostgreSQL не хранит основной бинарный сигнал.

---

## Файловая структура

Целевой layout:

```text
/srv/complex_eeg/
  upload_tmp/
    {upload_session_id}/
  experiments/
    {experiment_id}/
      source/
        signal.bin
        experiment.json
        journal.ndjson
        app.log
      validation/
        validation_report.json
  pipeline_results/
    {experiment_id}/
      runs/
        {pipeline_run_id}/
          result_manifest.json
          logs/
          artifacts/
```

Правила:

- `source/` immutable после `accepted`;
- pipeline writes only в `pipeline_results`;
- временные файлы имеют suffix `.part`;
- сервер не отдаёт файлы напрямую по filesystem path.

---

## PostgreSQL tables

### `experiments`

Основная карточка эксперимента.

```text
id UUID primary key
experiment_id text unique not null
display_name text not null
status text not null
source_path text null
validation_report_path text null
metadata_json jsonb null
validation_error_code text null
validation_error_message text null
processing_error_code text null
processing_error_message text null
uploaded_at timestamptz null
accepted_at timestamptz null
created_at timestamptz not null
updated_at timestamptz not null
```

### `upload_sessions`

```text
id text primary key -- ULID
experiment_id text not null
status text not null
tmp_path text not null
client_id text null
expected_files jsonb not null
uploaded_files jsonb not null
created_at timestamptz not null
completed_at timestamptz null
expires_at timestamptz not null
```

`client_id` — логический идентификатор upload-клиента, полученный auth layer.
Для MVP ручной загрузки через Web UI используется `web_ui`. Это не raw token,
не cookie и не `AUTH_SECRET`. Когда DB owner добавит поля владения
экспериментом, пользовательская принадлежность должна храниться явно, например
через `uploaded_by_user_id` / `owner_user_id`.

### `experiment_events`

Append-only история ключевых событий.

```text
id UUID primary key
experiment_id text not null
event_type text not null
from_status text null
to_status text null
message text null
details jsonb null
created_at timestamptz not null
```

### `source_files`

Файлы исходного пакета, принятые сервером.

```text
id UUID primary key
experiment_id text not null
name text not null
relative_path text not null
size_bytes bigint not null
sha256 text null
created_at timestamptz not null
```

При переходе эксперимента в `accepted` сервер выполняет `stat()` для каждого
source file и сохраняет `size_bytes`. Web DTO `source_files.size_bytes` берёт
значение из этой таблицы, а не вычисляет размер при каждом запросе.

`relative_path` относителен директории `source/`. Абсолютные пути в API не
возвращаются.

### `pipeline_runs`

```text
id text primary key -- ULID
experiment_id text not null
status text not null
trigger_type text not null
pipeline_version text null
params_json jsonb null
result_path text null
heartbeat_at timestamptz null
error_code text null
error_message text null
started_at timestamptz null
finished_at timestamptz null
created_at timestamptz not null
```

Допустимые `trigger_type`:

```text
auto_primary
manual_repeat
```

### `pipeline_artifacts`

```text
id text primary key -- ULID artifact_id
pipeline_run_id text not null
experiment_id text not null
name text not null
kind text not null
relative_path text not null
media_type text null
size_bytes bigint null
sha256 text null
created_at timestamptz not null
```

`relative_path` всегда относителен директории конкретного `pipeline_run_id`.
Абсолютные пути в API не возвращаются.

### `audit_events`

События безопасности и административные действия, не обязательно связанные с
конкретным экспериментом.

```text
id UUID primary key
actor_user_id UUID null
actor_client_id text null
event_type text not null
experiment_id text null
pipeline_run_id text null
ip_address text null
user_agent text null
details jsonb null
created_at timestamptz not null
```

В эту таблицу пишутся:

- web login success/failure;
- logout;
- repeat pipeline run;
- artifact download denied;
- admin/user management actions, когда они появятся.

### `users`

Первый стенд может использовать минимальную таблицу пользователей web UI:

```text
id UUID primary key
username text unique not null
password_hash text not null
role text not null
is_active boolean not null
created_at timestamptz not null
```

---

## Миграции

Используется Alembic.

Правила:

- все изменения схемы идут через migration files;
- ручные изменения БД на сервере запрещены;
- migration должна быть обратимой там, где это разумно;
- перед рискованной migration выполняется backup;
- CI запускает проверку миграций после появления server-кода.

Команды:

```bash
alembic revision --autogenerate -m "create experiments"
alembic upgrade head
alembic downgrade -1
```

`alembic/env.py` должен читать настройки подключения через `app.core.config`, где
`DATABASE_URL` собирается из `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`,
`POSTGRES_USER`, `POSTGRES_PASSWORD`, если не задан явно.

---

## `metadata_json`

`experiments.metadata_json` хранит поле `metadata` из `experiment.json` как есть.
Если `metadata` отсутствует, сохраняется пустой объект `{}`.

Полный `experiment.json` остаётся в файловом хранилище как исходный документ.

---

## Консистентность БД и файлов

Для accepted эксперимента должны быть истинны оба условия:

- в PostgreSQL есть запись `experiments.status = accepted`;
- `source_path` указывает на существующую директорию с обязательными файлами.

Порядок commit для successful validation:

1. проверить временный пакет;
2. создать permanent directory;
3. атомарно перенести файлы в permanent directory;
4. открыть DB transaction;
5. обновить `experiments`;
6. записать `experiment_events`;
7. commit.

Если шаги 2-3 успешны, а DB commit падает, cleanup должен пометить orphan
directory для ручного разбора. Сервер не удаляет такие данные автоматически без
логирования.

---

## Индексы

Минимальные индексы:

```text
experiments(experiment_id) unique
experiments(status)
experiments(uploaded_at)
upload_sessions(experiment_id)
upload_sessions(status)
source_files(experiment_id)
experiment_events(experiment_id, created_at)
pipeline_runs(experiment_id, created_at)
pipeline_runs(status)
pipeline_artifacts(pipeline_run_id)
pipeline_artifacts(experiment_id)
audit_events(created_at)
audit_events(actor_user_id, created_at)
users(username) unique
```

---

## Backup boundary

Бэкап должен включать:

- PostgreSQL database;
- `/srv/complex_eeg/experiments`;
- `/srv/complex_eeg/pipeline_results`;
- server configs, если они не восстанавливаются из Git/Ansible.

`upload_tmp` не является ценным долговременным хранилищем.

---

## Проверки реализации

Минимальные тесты:

- `experiment_id` нельзя принять дважды;
- статусная история пишется при переходах;
- accepted experiment имеет source path;
- source path нельзя поменять обычным update;
- pipeline run создаётся отдельно от experiment;
- orphan file path не появляется при штатном successful flow.
