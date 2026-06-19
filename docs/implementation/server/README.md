# Server implementation

## Статус

Draft.

Раздел описывает реализацию серверной части `complex_eeg`: API, загрузку
экспериментов, хранение данных, валидацию, запуск обработки и серверную часть
веб-интерфейса.

---

## Документы

```text
server.md       - общий план реализации серверного приложения
api.md          - HTTP API и контракты между приложением, web и сервером
upload.md       - загрузочные сессии и приём пакетов экспериментов через Web UI
storage.md      - PostgreSQL, файловое хранилище и миграции
validation.md   - реализация валидатора пакета эксперимента
pipeline.md     - запуск и повторный запуск обработки
web_backend.md  - backend-контракты для веб-интерфейса
```

---

## Базовые решения первого стенда

- Язык: Python 3.12.
- HTTP framework: FastAPI.
- База данных: PostgreSQL.
- ORM/migrations: SQLAlchemy + Alembic.
- Формат API: JSON over HTTP.
- Загрузка файлов: Web UI + upload session + multipart file upload.
- Идентификаторы session/run: ULID.
- Формат `experiment_id`: `^[a-zA-Z0-9_-]{1,64}$`.
- Фоновые задачи первого этапа: отдельный worker-процесс или контейнер,
  запускаемый через Docker Compose.
- Web-auth: HTTP-only session cookie.

Эти решения фиксируют первый реализуемый вариант. Они не меняют архитектурные
принципы: запись ЭЭГ остаётся локальной, Flutter создаёт experiment package,
сервер принимает только завершённые эксперименты через Web UI, исходные файлы не
переписываются.
