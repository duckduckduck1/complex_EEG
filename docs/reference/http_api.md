# HTTP API

Документ фиксирует HTTP API первого серверного стенда. MVP обслуживает Web UI,
через который пользователь вручную загружает готовые EEG experiment packages.
Прямое API для Flutter-приложения является будущим расширением.

---

## Принципы

1. Все mutating endpoints требуют аутентификации.
2. Загрузка эксперимента идёт через upload session.
3. Сервер возвращает стабильные `error_code`.
4. Исходные файлы не изменяются после принятия.
5. Web UI читает данные через API, а не напрямую из PostgreSQL или файловой
   системы.

---

## Версионирование

Базовый префикс:

```text
/api/v1
```

Breaking changes требуют нового префикса версии. Небольшие расширения ответа
допускаются без новой версии, если они обратно совместимы.

---

## Идентификаторы

### `experiment_id`

Допустимый формат:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Сервер отклоняет `experiment_id`, если он содержит `/`, `\`, `.`, пробелы,
unicode-символы или длину больше 64 символов. Проверка выполняется до создания
upload session и повторяется во время валидации `experiment.json`.

### `upload_session_id`

Формат: ULID, генерируется сервером.

### `pipeline_run_id`

Формат: ULID, генерируется сервером.

### `artifact_id`

Формат: ULID, генерируется pipeline worker для каждого артефакта и сохраняется в
`result_manifest.json` и PostgreSQL.

---

## Аутентификация

### Web UI

Web UI использует HTTP-only session cookie. Bearer token для web UI не
используется. На первом этапе допустим простой login/password для сотрудников
лаборатории.

Текущая реализация:

- `POST /api/v1/web/auth/login` проверяет username/password;
- успешный login выставляет signed HTTP-only cookie;
- `GET /api/v1/web/auth/me` возвращает текущего пользователя;
- `POST /api/v1/web/auth/logout` удаляет cookie в браузере;
- production upload endpoints требуют валидную web-auth cookie.

Mutating web endpoints дополнительно защищаются SameSite cookie и CSRF token,
если web UI работает как browser SPA.

### Future Flutter/API clients

Прямой upload из Flutter-приложения в MVP не используется. Если он появится
позже, для него будет добавлен отдельный client auth механизм:

```http
Authorization: Bearer <token>
```

Этот будущий механизм не должен менять upload lifecycle.

---

## CORS

Первый стенд работает как single-origin приложение за nginx: web UI и API
доступны с одного origin. CORS по умолчанию выключен.

Для локальной разработки можно включить allowlist origin через environment
variable, но wildcard `*` запрещён для authenticated endpoints.

---

## Request ID

Каждый HTTP response содержит header:

```http
X-Request-ID: <request_id>
```

Если клиент передал `X-Request-ID`, сервер переиспользует его при безопасном
формате. Если header отсутствует или некорректен, сервер генерирует новый id.

`request_id` пишется в structured request log и позволяет связать ошибку в UI,
HTTP response и запись в `docker compose logs api`.

---

## Общий формат ошибки

```json
{
  "error_code": "upload.session_not_found",
  "message": "Upload session was not found",
  "details": {
    "upload_session_id": "..."
  }
}
```

HTTP status отражает класс ошибки:

```text
400 - некорректный запрос
401 - нет аутентификации
403 - нет доступа
404 - объект не найден
409 - конфликт состояния или дубль experiment_id
413 - файл или пакет превышает лимит
422 - прикладная валидация входа
500 - внутренняя ошибка сервера
```

---

## Upload API

### Создать upload session

```http
POST /api/v1/uploads
```

Request:

```json
{
  "experiment_id": "exp_2026_001",
  "display_name": "exp1",
  "expected_files": [
    "signal.bin",
    "experiment.json"
  ]
}
```

`experiment_id` должен соответствовать regex `^[a-zA-Z0-9_-]{1,64}$`.

Response:

```json
{
  "upload_session_id": "01HX...",
  "experiment_id": "exp_2026_001",
  "status": "uploading",
  "upload_base_url": "/api/v1/uploads/01HX...",
  "expires_at": "2026-06-18T10:00:00Z"
}
```

Текущая реализация принимает `display_name` для совместимости с будущим Web UI,
но не сохраняет его в `upload_sessions`: в таблице нет такого поля. Финальное
решение должно быть принято DB owner: хранить display name в `experiments` при
создании session или добавить отдельное поле/metadata для upload session.

Ошибки:

- `auth.required`;
- `auth.forbidden`;
- `experiment.already_exists`;
- `upload.session_already_active`;
- `request.invalid_payload`.

### Загрузить файл

```http
PUT /api/v1/uploads/{upload_session_id}/files/{file_name}
Content-Type: application/octet-stream
```

Разрешённые имена первого этапа:

```text
signal.bin
experiment.json
journal.ndjson
app.log
```

Сервер сохраняет файл во временную директорию upload session.

Response:

```json
{
  "upload_session_id": "01HX...",
  "experiment_id": "exp_2026_001",
  "status": "uploading",
  "expected_files": [
    "experiment.json",
    "signal.bin"
  ],
  "uploaded_files": [
    "experiment.json"
  ],
  "expires_at": "2026-06-18T10:00:00Z"
}
```

Реализация пишет файл во временный `.part` и после успешной записи переносит его
в финальное имя. Если request превышает `UPLOAD_MAX_SIZE`, сервер возвращает
`413 upload.file_too_large`.

### Получить статус upload session

```http
GET /api/v1/uploads/{upload_session_id}
```

Response:

```json
{
  "upload_session_id": "01HX...",
  "experiment_id": "exp_2026_001",
  "status": "uploading",
  "expected_files": [
    "experiment.json",
    "signal.bin"
  ],
  "uploaded_files": [
    "experiment.json"
  ],
  "expires_at": "2026-06-18T10:00:00Z"
}
```

Web UI использует endpoint после перезагрузки страницы, если сохранил
`upload_session_id` в browser state.

### Отменить upload session

```http
DELETE /api/v1/uploads/{upload_session_id}
```

Отмена переводит session в `cancelled`, а связанный эксперимент в
`upload_cancelled`. Повторная отмена уже отменённой session возвращает `200` с
текущим статусом.

### Завершить загрузку

```http
POST /api/v1/uploads/{upload_session_id}/complete
```

Response:

```json
{
  "upload_session_id": "01HX...",
  "experiment_id": "exp_2026_001",
  "status": "accepted",
  "accepted": true,
  "validation_report_scope": "permanent",
  "signal_size_bytes": 4000,
  "sample_count": 1000,
  "source_files": [
    {
      "name": "signal.bin",
      "relative_path": "signal.bin",
      "size_bytes": 4000,
      "sha256": "..."
    }
  ],
  "errors": [],
  "warnings": []
}
```

В текущей реализации первого стенда `complete` синхронно запускает validation.
Если пакет валиден, сервер загружает source-файлы в MinIO bronze, сохраняет
validation report и возвращает `status = accepted`. Если пакет невалиден,
возвращается `status = failed`, `accepted = false`,
`validation_report_scope = upload_tmp` и список validation errors.

Accepted upload считается committed только после успешной загрузки source-файлов
в MinIO bronze, проверки читаемости объектов, одной PostgreSQL transaction с
row-level lock на `upload_sessions` и успешного commit. В этой transaction
пишутся `upload_sessions`, `experiments`, `source_files`,
`upload_storage_events`, `pipeline_runs` и `experiment_events`.

Если PostgreSQL commit падает после successful MinIO upload, сервер best-effort
записывает MinIO objects в `upload_orphan_objects` со статусом
`pending_cleanup`. Повторный `complete` выполняет retry из
`upload_tmp/{upload_session_id}/source`.

Идемпотентность:

- если session уже `accepted`, сервер возвращает `200` со статусом `accepted`;
- если session `cancelled`, `expired` или `failed`, сервер возвращает `409`.

Ошибки:

- `upload.incomplete`;
- `upload.session_state_conflict`;
- `object_storage.unavailable`.

### Dev/test upload bridge

Пока production Web UI upload ещё не реализован, сервер содержит временные
endpoint'ы для локальной проверки файлового upload flow:

```http
POST /api/v1/dev/uploads/process-local-folder
POST /api/v1/dev/uploads/process-zip?upload_session_id=...&experiment_id=...
```

Оба endpoint'а доступны только при:

```text
APP_ENV in local/dev/test
ENABLE_LOCAL_UPLOAD_ENDPOINT=true
```

`process-local-folder` принимает путь к папке на серверной машине и не должен
использоваться из browser UI. `process-zip` принимает raw body с
`Content-Type: application/zip`, безопасно распаковывает архив во временную
директорию и затем запускает тот же staging/validation/promotion flow.

Правила zip endpoint'а:

- архив может содержать `signal.bin` и `experiment.json` в корне;
- архив может содержать одну верхнеуровневую папку с EEG-пакетом внутри;
- `upload_session_id` валидируется как ULID до распаковки архива;
- zip entries с path traversal отклоняются;
- API response не возвращает абсолютные filesystem paths.

Этот dev/test bridge не заменяет production upload lifecycle. Когда появится
Web UI upload, он должен использовать authenticated upload session из БД.

---

## Experiment Status API

### Получить статус эксперимента

```http
GET /api/v1/experiments/{experiment_id}/status
```

Response:

```json
{
  "experiment_id": "exp_2026_001",
  "status": "processing",
  "upload_status": "uploaded",
  "validation_status": "accepted",
  "processing_status": "processing",
  "updated_at": "2026-06-17T10:05:00Z",
  "last_error": null
}
```

Для отменённых или истёкших upload sessions response может содержать:

```json
{
  "experiment_id": "exp_2026_001",
  "status": "upload_expired",
  "upload_status": "expired",
  "validation_status": null,
  "processing_status": null,
  "last_error": {
    "error_code": "upload.session_expired",
    "message": "Upload session expired before completion"
  }
}
```

### Получить список серверных статусов

```http
POST /api/v1/experiments/status-batch
```

Request:

```json
{
  "experiment_ids": [
    "exp_2026_001",
    "exp_2026_002"
  ]
}
```

Ограничение:

```text
max 100 experiment_ids per request
```

Если список больше 100 элементов, сервер возвращает `422 request.too_many_ids`.

В MVP endpoint используется Web UI или служебными инструментами. Flutter может
использовать его позже, если появится прямой режим синхронизации статусов.

---

## Web API

### Список экспериментов

```http
GET /api/v1/web/experiments?status=accepted&limit=50&offset=0
```

Response:

```json
{
  "items": [
    {
      "experiment_id": "exp_2026_001",
      "display_name": "exp1",
      "status": "processed",
      "uploaded_at": "2026-06-17T10:01:00Z",
      "updated_at": "2026-06-17T10:20:00Z"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

На первом стенде `total` вычисляется через `COUNT(*)`. Для лабораторного масштаба
в сотни экспериментов это приемлемо. При росте данных endpoint должен перейти на
cursor pagination или приблизительную оценку total.

### Карточка эксперимента

```http
GET /api/v1/web/experiments/{experiment_id}
```

Response содержит:

- метаданные;
- текущий статус;
- ошибки валидации/обработки;
- ссылки на исходные файлы, если скачивание разрешено;
- список pipeline runs;
- ссылки на результаты обработки.

### Повторный запуск обработки

```http
POST /api/v1/web/experiments/{experiment_id}/pipeline-runs
```

Повторный запуск доступен только web-пользователю с правом оператора или
администратора. На первом этапе роль может быть простой: authenticated user with
operator flag.

---

## Health API

```http
GET /health
GET /ready
GET /metrics
```

`/health` проверяет, что процесс жив.

`/ready` проверяет:

- подключение к PostgreSQL;
- доступность `EXPERIMENTS_DIR`;
- доступность `UPLOAD_TMP_DIR`;
- доступность `PIPELINE_RESULTS_DIR`.

Если хотя бы одна проверка не проходит, endpoint возвращает HTTP `503` и
`status = not_ready`. Проверка миграций не входит в текущий `/ready` и будет
добавлена после появления initial Alembic migrations.

`/metrics` отдаёт Prometheus metrics.
