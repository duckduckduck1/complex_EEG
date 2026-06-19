# server.md

## Статус

Draft.

Документ описывает реализацию серверного приложения `complex_eeg`: из каких
модулей оно состоит, как обрабатывает эксперимент, где проходит граница
ответственности и какие правила должны выдерживаться в коде.

---

## Владелец

Серверное звено проекта `complex_eeg`.

Ответственность:

- аутентификация клиентов;
- создание upload sessions;
- приём файлов эксперимента;
- запуск валидации;
- сохранение метаданных и статусов;
- запуск первичной обработки;
- API для веб-интерфейса;
- API для будущих клиентских интеграций;
- эксплуатационные endpoints и метрики.

---

## Назначение

Сервер принимает завершённые локальные эксперименты, проверяет их, сохраняет как
серверные данные и запускает обработку. Сервер не участвует в live-записи ЭЭГ и
не должен быть обязательным условием для локального эксперимента.

Единица серверной обработки — один эксперимент с одним `experiment_id`.

---

## Базовый стек

Для первого стенда используется:

```text
Python 3.12
FastAPI
Uvicorn
PostgreSQL
SQLAlchemy
Alembic
Pydantic
pytest
```

Причина выбора: стек хорошо подходит для HTTP API, валидации JSON-контрактов,
работы с PostgreSQL и фоновых задач обработки. Он также совместим с уже
подготовленным Docker/CI skeleton.

---

## Non-goals

Серверное приложение на первом этапе не реализует:

- live-streaming сигнала;
- управление BLE-устройством;
- управление фотобиомодуляцией;
- автоматическое определение фаз сна;
- ML/MLOps;
- сложную multi-tenant модель;
- публичную регистрацию пользователей;
- редактирование исходного `signal.bin`.

---

## Модульная структура

Целевая структура server-кода:

```text
server/
  app/
    main.py
    core/
      config.py
      logging.py
      security.py
      errors.py
    api/
      deps.py
      routes_auth.py
      routes_upload.py
      routes_experiments.py
      routes_web_auth.py
      routes_web_experiments.py
      routes_web_artifacts.py
      routes_web_pipeline.py
      routes_health.py
    domain/
      statuses.py
      errors.py
      schemas.py
    services/
      auth_service.py
      upload_service.py
      validation_service.py
      experiment_service.py
      pipeline_service.py
      file_storage.py
    repositories/
      experiments.py
      upload_sessions.py
      events.py
      pipeline_runs.py
    db/
      session.py
      models.py
      migrations/
    workers/
      pipeline_worker.py
    tests/
```

### Правило

HTTP handlers не содержат бизнес-логику. Они валидируют вход, вызывают service
layer и возвращают DTO. Работа с PostgreSQL идёт через repositories. Работа с
файлами идёт через `file_storage`.

---

## Основной lifecycle эксперимента

```text
web user authenticates
  -> create upload session
  -> upload files
  -> complete upload
  -> validate package
  -> accept or reject
  -> store metadata and immutable source files
  -> start primary pipeline run
  -> expose status to web
```

Сервер не создаёт `accepted` до успешной валидации.

Flutter-приложение в MVP не является upload-клиентом сервера. Оно создаёт
локальный пакет эксперимента. Web UI выполняет ручную загрузку этого пакета.
Прямой Flutter upload может быть добавлен позже без изменения серверного
lifecycle.

---

## Статусная модель

Канонические статусы эксперимента:

```text
uploading
uploaded
upload_cancelled
upload_expired
validating
accepted
validation_failed
processing
processed
processing_failed
```

Разрешённые переходы:

```text
uploading -> uploaded
uploading -> upload_cancelled
uploading -> upload_expired
uploaded -> validating
validating -> accepted
validating -> validation_failed
accepted -> processing
processing -> processed
processing -> processing_failed
processing_failed -> processing
processed -> processing
```

Повторный переход в `processing` после `processed` или `processing_failed`
допускается только при ручном повторном запуске обработки.

`upload_cancelled` и `upload_expired` являются терминальными статусами
незавершённой отправки. Такие эксперименты не считаются принятыми сервером и по
умолчанию не показываются в основном списке web UI.

---

## Идентификаторы

### `experiment_id`

Формат:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Правила:

- проверяется при создании upload session;
- повторно проверяется валидатором по `experiment.json`;
- используется в filesystem paths только после успешной проверки;
- любые `/`, `\`, `.`, пробелы и unicode-символы запрещены.

### `upload_session_id`

Формат: ULID.

### `pipeline_run_id`

Формат: ULID.

---

## Ошибки

API возвращает прикладные ошибки в едином формате:

```json
{
  "error_code": "validation.missing_file",
  "message": "Required file signal.bin is missing",
  "details": {
    "file": "signal.bin"
  }
}
```

Правила:

- `error_code` стабилен и пригоден для UI;
- `message` человекочитаемый;
- `details` не содержит секретов;
- технический stack trace не возвращается клиенту;
- полный технический контекст пишется в серверный лог.

---

## Конкурентность и идемпотентность

Сервер должен защищаться от дублей:

- `experiment_id` уникален для принятого эксперимента;
- активная upload session блокирует параллельную загрузку того же
  `experiment_id`, если не включён явный restart session;
- повторный `complete upload` не должен создавать второй эксперимент;
- повторная обработка создаёт новый `pipeline_run`, а не переписывает историю.

---

## Конфигурация

Сервер читает конфигурацию из environment variables:

```text
APP_ENV
APP_BASE_URL
POSTGRES_HOST
POSTGRES_PORT
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
EXPERIMENTS_DIR
PIPELINE_RESULTS_DIR
UPLOAD_TMP_DIR
AUTH_SECRET
UPLOAD_MAX_SIZE
LOG_DIR
UPLOAD_SESSION_TTL_HOURS
PIPELINE_VERSION
PIPELINE_POLL_INTERVAL_SECONDS
PIPELINE_MAX_RUN_DURATION_HOURS
PIPELINE_STUCK_HEARTBEAT_MINUTES
SESSION_COOKIE_SECURE
```

Файл `.env` создаётся инфраструктурным слоем и не хранится в Git.

---

## Наблюдаемость

Минимальные endpoints:

```text
GET /health
GET /ready
GET /metrics
```

Минимальные метрики:

- количество upload sessions;
- количество успешных/ошибочных загрузок;
- ошибки валидации по коду;
- текущие статусы экспериментов;
- длительность валидации;
- длительность обработки;
- ошибки pipeline;
- доступность PostgreSQL.

---

## Проверки готовности

Server implementation считается готовым к первому запуску, если:

- приложение стартует через Uvicorn;
- `/health` отвечает без доступа к PostgreSQL;
- `/ready` проверяет PostgreSQL и файловые директории;
- миграции применяются;
- upload session создаётся только после web-auth;
- обязательные файлы принимаются и сохраняются;
- валидатор может перевести эксперимент в `accepted` или `validation_failed`;
- pipeline worker получает задачу после `accepted`;
- статусы доступны web backend.
