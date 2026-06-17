# api.md

## Статус

Draft.

Документ фиксирует HTTP API первого серверного стенда. API обслуживает два типа
клиентов: Flutter-приложение и веб-интерфейс.

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

### Flutter-приложение

Первый стенд использует client token:

```http
Authorization: Bearer <token>
```

Токен хранится в конфигурации приложения и сверяется сервером. Позже механизм
может быть заменён на OAuth/device flow без изменения upload lifecycle.

### Web UI

Web UI использует HTTP-only session cookie. Bearer token для web UI не
используется. На первом этапе допустим простой login/password для сотрудников
лаборатории.

Mutating web endpoints дополнительно защищаются SameSite cookie и CSRF token,
если web UI работает как browser SPA.

---

## CORS

Первый стенд работает как single-origin приложение за nginx: web UI и API
доступны с одного origin. CORS по умолчанию выключен.

Для локальной разработки можно включить allowlist origin через environment
variable, но wildcard `*` запрещён для authenticated endpoints.

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
  "client_created_at": "2026-06-17T10:00:00Z",
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
  "upload_base_url": "/api/v1/uploads/01HX..."
}
```

Ошибки:

- `auth.invalid_token`;
- `experiment.already_accepted`;
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
  "uploaded_files": [
    "experiment.json"
  ],
  "expires_at": "2026-06-18T10:00:00Z"
}
```

Flutter-приложение использует endpoint после рестарта, если сохранило
`upload_session_id`.

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
  "experiment_id": "exp_2026_001",
  "status": "validating"
}
```

После `complete` сервер запускает валидацию.

Идемпотентность:

- если session уже `completed` или `validating`, сервер возвращает `200` с
  текущим статусом;
- второй validation job не создаётся;
- если session уже `accepted`, сервер возвращает `200` со статусом `accepted`;
- если session `cancelled`, `expired` или `failed`, сервер возвращает `409`.

---

## Experiment API для приложения

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

### Получить список серверных статусов для локальных экспериментов

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

Этот endpoint нужен Flutter-приложению, чтобы показывать локальному
пользователю статусы `не отправлен / отправлен / ошибка / принят`.

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

`/metrics` отдаёт Prometheus metrics.
