# Хранение: MinIO bronze и ссылки в PostgreSQL

Документ описывает реализацию хранилища серверной части: PostgreSQL, MinIO,
локальный staging, SQL init scripts и правила консистентности.

---

## Решение

Используются три зоны хранения:

1. PostgreSQL — метаданные, статусы, события, ссылки на объекты MinIO.
2. MinIO bronze — immutable source-пакет после `accepted`.
3. Локальная файловая система — staging/cache (`upload_tmp`), validation reports,
   pipeline results.

PostgreSQL не хранит основной бинарный сигнал.

Исполняемая схема PostgreSQL: `scripts/db_scripts/010_schema.sql`.

---

## MinIO layout (bronze)

```text
s3://lakehouse-bronze/eeg/{experiment_id}/signal.bin
s3://lakehouse-bronze/eeg/{experiment_id}/experiment.json
```

Buckets создаёт `scripts/minio/010_init_buckets.sh` через сервис `minio-init`.

---

## Локальная файловая структура (staging и pipeline)

```text
/srv/complex_eeg/
  upload_tmp/
    {upload_session_id}/
      source/
        signal.bin
        experiment.json
        journal.ndjson
        app.log
      validation_report.json
  experiments/
    {experiment_id}/
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

- `upload_tmp` — только до успешной валидации;
- после `accepted` source-файлы живут в MinIO bronze;
- локальная копия `experiments/{experiment_id}/source/` удаляется сразу после
  успешной загрузки в MinIO bronze и успешного PostgreSQL commit;
- pipeline writes only в `pipeline_results`;
- временные файлы имеют suffix `.part`.

---

## PostgreSQL tables

### `experiments`

Основная карточка эксперимента.

```text
id UUID primary key
experiment_id text unique not null
display_name text not null
status text not null
storage_bucket text null
storage_prefix text null
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

Для защиты от race conditions в PostgreSQL есть partial unique index:

```text
unique upload_sessions(experiment_id)
where status in ('created', 'uploading', 'completed', 'validating')
```

Он запрещает две активные upload sessions для одного `experiment_id` даже если
два API-процесса одновременно прошли application-level precheck.

`client_id` — логический идентификатор upload-клиента, полученный auth layer.
Для MVP ручной загрузки через Web UI используется `web_ui`. Это не raw token,
не cookie и не `AUTH_SECRET`. Когда DB owner добавит поля владения
экспериментом, пользовательская принадлежность должна храниться явно, например
через `uploaded_by_user_id` / `owner_user_id`.

### `upload_storage_events`

Журнал границы между upload session, MinIO и accepted metadata transaction.
Записи создаются в той же PostgreSQL transaction, что и `experiments`,
`source_files`, `pipeline_runs` и `experiment_events` для accepted upload.

```text
id UUID primary key
upload_session_id text not null
experiment_id text not null
event_type text not null
status text not null
bucket text null
storage_prefix text null
object_key text null
message text null
details jsonb null
created_at timestamptz not null
```

Минимальные события:

```text
minio_object_uploaded
source_package_accepted
```

### `upload_orphan_objects`

Best-effort журнал MinIO objects, которые были загружены до PostgreSQL commit,
но основной accepted commit упал и был откатан. Таблица нужна для cleanup/manual
audit и пишется отдельной transaction после rollback основной transaction.

```text
id UUID primary key
upload_session_id text not null
experiment_id text not null
bucket text not null
storage_prefix text not null
object_key text not null
relative_path text not null
size_bytes bigint not null
sha256 text null
reason text not null
status text not null
details jsonb null
created_at timestamptz not null
resolved_at timestamptz null
```

Начальный статус:

```text
pending_cleanup
```

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
bucket text not null
object_key text not null
size_bytes bigint not null
sha256 text null
created_at timestamptz not null
unique (bucket, object_key)
```

`relative_path` — имя файла внутри `storage_prefix`. API не возвращает полные
S3 URI.

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

`password_hash` первого стенда хранится в формате:

```text
pbkdf2_sha256$iterations$salt$hash
```

Hash создаётся server auth service. Plain text пароль в PostgreSQL не хранится.

Первый пользователь создаётся через server admin CLI:

```bash
complex-eeg users create --username admin --role admin
```

---

## Инициализация схемы

Первый стенд создаёт PostgreSQL-схему через SQL init scripts:

```text
scripts/db_scripts/010_schema.sql
scripts/db_scripts/090_seed_dev.sql
```

Docker Compose монтирует `scripts/db_scripts` в
`/docker-entrypoint-initdb.d` контейнера `postgres`.

Правила:

- исполняемая схема описывается в SQL, не в Alembic autogenerate;
- `server/app/db/models.py` должен оставаться синхронизированным с SQL;
- ручные изменения БД на сервере запрещены;
- Alembic остаётся для будущих инкрементальных migration files после первого
  стенда.

Проверка схемы:

```bash
psql "$DATABASE_URL" -f scripts/db_scripts/checks/001_schema_readiness.sql
```

---

## Alembic (после первого стенда)

Alembic skeleton остаётся в `server/alembic`, но не заменяет SQL init scripts.

`alembic/env.py` читает подключение через `app.core.config`.

---

## `metadata_json`

`experiments.metadata_json` хранит поле `metadata` из `experiment.json` как есть.
Если `metadata` отсутствует, сохраняется пустой объект `{}`.

Полный `experiment.json` остаётся в MinIO bronze как исходный объект.

---

## Консистентность БД и MinIO

Для accepted эксперимента должны быть истинны оба условия:

- в PostgreSQL есть запись `experiments.status = accepted` с `storage_bucket` и
  `storage_prefix`;
- объекты `signal.bin` и `experiment.json` существуют по ключам из `source_files`.

Порядок commit для successful validation:

1. открыть PostgreSQL transaction;
2. заблокировать строку `upload_sessions` через `SELECT ... FOR UPDATE`;
3. проверить временный пакет в `upload_tmp`;
4. проверить отсутствие accepted эксперимента с тем же `experiment_id`;
5. удалить uncommitted локальную `experiments/{experiment_id}/`, если это retry
   после failed commit;
6. загрузить файлы в MinIO bronze;
7. проверить, что загруженные объекты читаются из MinIO;
8. обновить `upload_sessions.status = accepted`;
9. записать `experiments`;
10. записать `source_files` с `bucket` + `object_key`;
11. записать `upload_storage_events`;
12. записать `pipeline_runs` и `experiment_events`;
13. commit;
14. удалить локальную `experiments/{experiment_id}/source/`.

`SELECT ... FOR UPDATE` держит lock до PostgreSQL commit/rollback и защищает от
параллельного `complete` одной upload session.

Если MinIO upload или проверка читаемости объекта падает, PostgreSQL не получает
accepted-записей, локальная promoted-директория удаляется, а canonical retry
source остаётся в `upload_tmp/{upload_session_id}/source`. Если MinIO upload
успешен, а PostgreSQL commit падает, PostgreSQL transaction откатывается,
локальная source-копия не удаляется, а MinIO objects считаются orphan candidates
для последующего cleanup/manual audit. После rollback сервер best-effort пишет
эти объекты в `upload_orphan_objects`; если и этот лог не записался, исходное
правило retry сохраняется через `upload_tmp` и локальную source-копию.

---

## Индексы

Минимальные индексы:

```text
experiments(experiment_id) unique
experiments(status)
experiments(uploaded_at)
upload_sessions(experiment_id)
upload_sessions(status)
upload_sessions(experiment_id) unique where status is active
upload_storage_events(upload_session_id, created_at)
upload_storage_events(experiment_id, created_at)
upload_orphan_objects(status, created_at)
upload_orphan_objects(experiment_id, created_at)
source_files(experiment_id)
source_files(bucket, object_key) unique
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
- MinIO data volume (`MINIO_DATA_DIR`);
- `/srv/complex_eeg/pipeline_results`;
- server configs, если они не восстанавливаются из Git/Ansible.

`upload_tmp` не является ценным долговременным хранилищем.

---

## Проверки реализации

Минимальные тесты:

- `experiment_id` нельзя принять дважды;
- `source_files (bucket, object_key)` нельзя продублировать;
- accepted experiment имеет `storage_bucket` и `storage_prefix`;
- pipeline run создаётся отдельно от experiment;
