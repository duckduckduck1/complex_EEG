# Веб-бэкенд и кабинет

Документ описывает backend-контракты для веб-интерфейса лаборатории.

---

## Назначение

Web backend отдаёт сотрудникам лаборатории список экспериментов, карточку
эксперимента, статусы, ошибки и результаты обработки. Он также является основным
MVP-клиентом для ручной загрузки experiment package на сервер. Веб-интерфейс не
читает PostgreSQL и файловое хранилище напрямую.

---

## Аутентификация

Доступ к web endpoints требует пользовательской аутентификации.

Первый стенд:

- username/password;
- password hash в PostgreSQL;
- HTTP-only session cookie;
- logout endpoint;
- создание пользователей через server admin CLI.

Bearer token для web UI не используется. Публичная регистрация не нужна.

Password hash algorithm:

```text
pbkdf2_sha256
```

На первом стенде используется `pbkdf2_sha256` из стандартной библиотеки Python,
чтобы не добавлять отдельную криптографическую зависимость до полноценного user
management. Формат хранения:

```text
pbkdf2_sha256$iterations$salt$hash
```

Если позже будет выбран `bcrypt` или `argon2`, миграция должна поддерживать
проверку старых hash'ей до принудительной смены пароля.

Cookie settings:

```text
HttpOnly=true
SameSite=Lax
Secure=${SESSION_COOKIE_SECURE}
Name=${SESSION_COOKIE_NAME}
TTL=${SESSION_TTL_HOURS}h
```

Для локального стенда:

```text
SESSION_COOKIE_SECURE=false
```

Для production-like HTTPS окружения:

```text
SESSION_COOKIE_SECURE=true
```

Mutating requests используют CSRF token, если web UI работает в браузере как SPA.

---

## Роли

Минимальные роли:

```text
viewer
operator
admin
```

Первый стенд может начать с `admin` для всех внутренних пользователей, но API
должен быть написан так, чтобы проверка роли была явной.

Права:

- `viewer` — просмотр списка, карточек, результатов;
- `operator` — загрузка экспериментов и повторный запуск обработки;
- `admin` — управление пользователями, служебные действия и права `operator`.

Пользователь первого стенда создаётся не через HTTP API, а через CLI:

```bash
complex-eeg users create --username admin --role admin
```

Подробности: `docs/implementation/server/admin_cli.md`.

---

## Endpoints

### Login

```http
POST /api/v1/web/auth/login
```

Request:

```json
{
  "username": "lab_user",
  "password": "..."
}
```

Response:

```json
{
  "user": {
    "username": "lab_user",
    "role": "operator"
  }
}
```

### Logout

```http
POST /api/v1/web/auth/logout
```

### Current user

```http
GET /api/v1/web/auth/me
```

### Upload experiment package

Web UI использует общий upload lifecycle из `upload.md`, но действует от имени
аутентифицированного web-пользователя.

```http
POST /api/v1/uploads
PUT /api/v1/uploads/{upload_session_id}/files/{file_name}
POST /api/v1/uploads/{upload_session_id}/complete
GET /api/v1/uploads/{upload_session_id}
DELETE /api/v1/uploads/{upload_session_id}
```

На первом production Web UI стенде форма принимает folder selection или
множественный выбор файлов пакета:

```text
folder selection
file selection
```

Поддержка `.zip archive` остаётся dev/test bridge или будущим production flow:
production UI не должен вызывать dev/test endpoint'ы.

Browser не должен отправлять абсолютные локальные пути пользователя на сервер как
часть API-контракта. Сервер получает только имена файлов внутри пакета и
содержимое файлов.

Минимальная UI-логика:

1. пользователь выбирает папку или отдельные файлы пакета;
2. web frontend читает/проверяет обязательные файлы, если platform API это
   позволяет;
3. сервер создаёт upload session;
4. файлы отправляются по allowlist;
5. complete запускает server validation;
6. пользователь видит статус upload/validation/processing.

### Experiment list

```http
GET /api/v1/web/experiments
```

Query parameters:

```text
status: optional experiment status
date_from: optional uploaded_at lower bound
date_to: optional uploaded_at upper bound
search: optional substring over display_name and experiment_id
limit: 1..100, default 50
offset: >= 0, default 0
sort: uploaded_at_desc | uploaded_at_asc | updated_at_desc | display_name_asc | status_asc
```

Response включает `total`, который на первом стенде считается через `COUNT(*)`.
Это приемлемо для лабораторного масштаба. При росте данных endpoint должен быть
переведён на cursor pagination или approximate total.

### Experiment details

```http
GET /api/v1/web/experiments/{experiment_id}
```

### Pipeline runs

```http
GET /api/v1/web/experiments/{experiment_id}/pipeline-runs
POST /api/v1/web/experiments/{experiment_id}/pipeline-runs
```

Pipeline run DTO:

```json
{
  "pipeline_run_id": "01HX...",
  "status": "succeeded",
  "trigger_type": "auto_primary",
  "pipeline_version": "dev",
  "started_at": "2026-06-17T10:10:00Z",
  "finished_at": "2026-06-17T10:20:00Z",
  "error_code": null,
  "error_message": null,
  "artifacts": [
    {
      "artifact_id": "01HY...",
      "name": "summary.json",
      "kind": "summary",
      "size_bytes": 1234,
      "media_type": "application/json"
    }
  ]
}
```

### Download artifact

```http
GET /api/v1/web/experiments/{experiment_id}/artifacts/{artifact_id}
```

Скачивание исходных файлов может быть отключено политикой лаборатории. Endpoint
должен проверять permission.

`artifact_id` — ULID из `result_manifest.json` и таблицы `pipeline_artifacts`.
Он не равен имени файла.

---

## Experiment list DTO

```json
{
  "experiment_id": "exp_2026_001",
  "display_name": "exp1",
  "status": "processed",
  "uploaded_at": "2026-06-17T10:01:00Z",
  "accepted_at": "2026-06-17T10:05:00Z",
  "last_pipeline_status": "succeeded",
  "last_error": null
}
```

---

## Experiment detail DTO

```json
{
  "experiment_id": "exp_2026_001",
  "display_name": "exp1",
  "status": "processed",
  "metadata": {},
  "source_files": [
    {
      "name": "signal.bin",
      "size_bytes": 1000000,
      "download_allowed": false
    }
  ],
  "validation": {
    "status": "accepted",
    "error": null
  },
  "pipeline_runs": [],
  "events": []
}
```

`source_files.size_bytes` берётся из таблицы `source_files`. Значение вычисляется
сервером через `stat()` при переходе эксперимента в `accepted` и не требует
чтения файла при каждом web-запросе.

`events` — массив событий из `experiment_events`:

```json
[
  {
    "event_type": "status_changed",
    "from_status": "validating",
    "to_status": "accepted",
    "message": "Experiment accepted",
    "created_at": "2026-06-17T10:05:00Z"
  }
]
```

---

## Ошибки

Web backend показывает прикладные ошибки:

- validation error;
- processing error;
- upload incomplete;
- artifact missing;
- permission denied.

Технические stack traces не возвращаются в web UI.

---

## Безопасность

Правила:

- web session cookie, если используется, должна быть HTTP-only;
- password hash хранится через `pbkdf2_sha256`;
- download endpoints проверяют path ownership;
- path traversal запрещён;
- ошибки auth не раскрывают, существует ли username;
- audit event пишется в PostgreSQL table `audit_events` для login/logout и
  repeat pipeline run.

---

## Backend route files

Целевая структура routes для web backend:

```text
routes_web_auth.py
routes_web_experiments.py
routes_web_artifacts.py
routes_web_pipeline.py
```

Один общий `routes_web.py` не используется, чтобы не смешивать auth,
эксперименты, скачивание файлов и действия с pipeline runs.

---

## Тесты

Минимальные тесты:

- unauthenticated user не видит список экспериментов;
- viewer не может запустить повторную обработку;
- operator может запустить repeat run;
- карточка experiment не содержит server filesystem path;
- download endpoint не принимает path traversal;
- login с неверным паролем возвращает 401.
