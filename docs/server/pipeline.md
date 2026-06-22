# Пайплайн обработки

## Принципы и границы

- Запускается только для `accepted` экспериментов; создаёт производные данные,
  исходный пакет не переписывается.
- Запуск повторяем; первичный запуск — автоматически после принятия, повторный —
  вручную.
- Ошибки обработки фиксируются (этап, причина, лог); работает в изолированной
  среде (Docker).
- Не входит: приём файлов, валидация структуры, веб-просмотр, ручная разметка,
  авто-определение фаз сна, ML/MLOps на текущем этапе.

---

Документ описывает реализацию серверного запуска пайплайна обработки.

---

## Назначение

Пайплайн запускается после успешной валидации эксперимента и создаёт производные
результаты. Он не изменяет исходные файлы.

---

## Решение первого стенда

Первичный запуск выполняется автоматически после перехода эксперимента в
`accepted`.

Повторный запуск выполняется вручную через web/API.

Пайплайн запускается отдельным worker-процессом или контейнером
`pipeline-worker`. API создаёт запись `pipeline_runs`, worker забирает pending
run и выполняет обработку.

---

## Очередь worker

Для первого стенда очередь реализуется через PostgreSQL polling.

Настройки:

```text
PIPELINE_POLL_INTERVAL_SECONDS=5
PIPELINE_VERSION=dev
PIPELINE_MAX_RUN_DURATION_HOURS=6
PIPELINE_STUCK_HEARTBEAT_MINUTES=15
```

`PIPELINE_VERSION` берётся из environment. На первом стенде значение по умолчанию
`dev`. В CI/CD его можно заменить на `git describe --tags` или commit SHA при
сборке образа.

Worker берёт задачу транзакционно:

```sql
SELECT id
FROM pipeline_runs
WHERE status = 'queued'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

После выбора run worker в той же транзакции переводит его в `running`, заполняет
`started_at` и `heartbeat_at`.

`FOR UPDATE SKIP LOCKED` обязателен, чтобы два worker-процесса не взяли один и
тот же run.

---

## Pipeline run lifecycle

```text
queued
running
succeeded
failed
cancelled
```

Связь со статусом эксперимента:

- `queued/running` переводит эксперимент в `processing`;
- `succeeded` переводит эксперимент в `processed`;
- `failed` переводит эксперимент в `processing_failed`.

---

## Создание primary run

После successful validation:

1. experiment переходит в `accepted`;
2. server создаёт `pipeline_runs(trigger_type = auto_primary)`;
3. experiment остаётся в `accepted`, пока задача только ожидает worker;
4. worker берёт run и переводит experiment в `processing`;
5. worker сохраняет результаты;
6. server/repository обновляет статус.

Если worker недоступен, run остаётся `queued`, а experiment может оставаться
`accepted` или перейти в `processing` только после фактического старта. Для
первого стенда предпочтительно:

```text
accepted -> processing только когда worker начал run
```

---

## Зависшие запуски

Watchdog запускается в том же `pipeline-worker` процессе. Перед каждым poll cycle
worker выполняет отдельный SQL-запрос, который ищет stuck runs и переводит их в
`failed`.

Worker обновляет `pipeline_runs.heartbeat_at` во время обработки. Частота
обновления:

```text
heartbeat interval = PIPELINE_STUCK_HEARTBEAT_MINUTES / 2
```

При значении `PIPELINE_STUCK_HEARTBEAT_MINUTES=15` heartbeat обновляется каждые
7 минут. Долгая обработка не должна оставлять `heartbeat_at` без обновления до
самого завершения run.

Run считается stuck, если выполнено хотя бы одно условие:

- `status = running` и `now() - heartbeat_at > PIPELINE_STUCK_HEARTBEAT_MINUTES`;
- `status = running` и `now() - started_at > PIPELINE_MAX_RUN_DURATION_HOURS`.

Watchdog job переводит stuck run в `failed`, заполняет:

```text
error_code = pipeline.run_stuck
error_message = Pipeline run exceeded heartbeat or max duration limit
```

После этого experiment переводится в `processing_failed`, если это был активный
run.

---

## Повторный запуск

Повторный запуск создаётся через:

```http
POST /api/v1/web/experiments/{experiment_id}/pipeline-runs
```

Требования:

- experiment должен быть `accepted`, `processed` или `processing_failed`;
- не должно быть активного `queued/running` run для этого experiment;
- пользователь должен быть аутентифицирован;
- причина повторного запуска логируется.

Повторный запуск не переписывает исходные файлы.

---

## Результаты

Результаты одного run лежат в отдельной директории:

```text
/srv/complex_eeg/pipeline_results/{experiment_id}/runs/{pipeline_run_id}/
  result_manifest.json
  logs/
  artifacts/
```

`result_manifest.json` описывает:

- pipeline version;
- input experiment id;
- started/finished timestamps;
- parameters;
- generated artifacts;
- warnings;
- errors.

Минимальная структура:

```json
{
  "pipeline_run_id": "01HX...",
  "experiment_id": "exp_2026_001",
  "pipeline_version": "dev",
  "status": "succeeded",
  "started_at": "2026-06-17T10:10:00Z",
  "finished_at": "2026-06-17T10:20:00Z",
  "params": {},
  "artifacts": [
    {
      "artifact_id": "01HY...",
      "name": "summary.json",
      "kind": "summary",
      "relative_path": "artifacts/summary.json",
      "media_type": "application/json",
      "size_bytes": 1234,
      "sha256": "..."
    }
  ],
  "warnings": [],
  "errors": []
}
```

`artifact_id` — ULID, сгенерированный worker/server для конкретного артефакта.
Это не имя файла и не filesystem path. API скачивания находит artifact по
`artifact_id`, проверяет, что `relative_path` остаётся внутри директории run, и
только после этого отдаёт файл.

---

## Версионирование результатов

Каждый повторный запуск создаёт новый `pipeline_run_id`.

Первое правило:

- UI показывает latest successful run как основной результат;
- старые runs остаются доступны для диагностики;
- удаление старых results возможно только отдельной retention policy.

---

## Ошибки

Worker сохраняет:

- `error_code`;
- короткое сообщение;
- internal technical log path;
- stage name;
- exit code, если запускался внешний процесс.

Пример:

```json
{
  "error_code": "pipeline.signal_read_failed",
  "message": "Pipeline could not read signal.bin",
  "stage": "load_input",
  "log_path": "/srv/complex_eeg/pipeline_results/exp/runs/run/logs/pipeline.log"
}
```

Этот объект является внутренним форматом для `result_manifest.json` или
служебного хранения. В API response абсолютный `log_path` не возвращается.
Клиентам доступны только `error_code`, `error_message` и, если разрешено,
artifact/download endpoint для логов через `artifact_id`.

---

## Изоляция

Pipeline worker не принимает HTTP-загрузки и не пишет в source storage. Доступы:

```text
read:  /srv/complex_eeg/experiments
write: /srv/complex_eeg/pipeline_results
write: /var/log/complex_eeg/pipeline
read/write: PostgreSQL pipeline status
```

---

## Метрики

Минимальные метрики:

- queued runs count;
- running runs count;
- run duration;
- failed runs count;
- latest successful run timestamp;
- failures by error_code.

---

## Тесты

Минимальные тесты:

- primary run создаётся после accepted;
- validation_failed не запускает pipeline;
- нельзя запустить второй active run;
- failed run переводит experiment в `processing_failed`;
- successful run переводит experiment в `processed`;
- повторный run создаёт новый result path;
- source files не изменяются;
- два worker не могут взять один `queued` run из-за `FOR UPDATE SKIP LOCKED`;
- stuck `running` run переводится в `failed`;
- artifact из manifest получает стабильный `artifact_id`.
