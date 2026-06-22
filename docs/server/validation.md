# Валидация пакета

Документ описывает серверный валидатор пакета эксперимента: его роль в потоке
приёмки, вход/выход и интеграцию со статусами. **Точные правила формата и коды
ошибок — в [reference/experiment_package.md](../reference/experiment_package.md)**
(он выверен по коду валидатора).

---

## Назначение

Валидатор проверяет, что загруженный пакет можно принять сервером и передать в
обработку. Он только читает файлы и не исправляет исходные данные.

---

## Вход

Валидатор получает после `complete upload`:

```text
upload_session_id
experiment_id
tmp_path
signal.bin
experiment.json
journal.ndjson (optional)
app.log (optional)
```

---

## Что проверяет

Кратко (точные правила — в reference):

- обязательные `signal.bin` и `experiment.json` существуют и читаются;
- `experiment.json` — валидный JSON-объект с обязательными полями;
- `experiment_id` совпадает с upload session и проходит regex
  `^[a-zA-Z0-9_-]{1,64}$`;
- `signal.bin` непустой, размер кратен 4; `sample_count = size / 4`;
- сегменты корректны и в пределах сигнала; метки и ФБМ-события — внутри своих
  сегментов.

### Защита от дубля

Валидатор повторно проверяет, что нет уже принятого эксперимента с тем же
`experiment_id` и что session всё ещё активна. Основная проверка дублей идёт при
создании upload session; повторная защищает от гонок и ручных повреждений
состояния.

---

## Выход

Успех:

```json
{
  "status": "accepted",
  "experiment_id": "exp_2026_001",
  "metadata": {},
  "storage_bucket": "lakehouse-bronze",
  "storage_prefix": "eeg/exp_2026_001/"
}
```

Ошибка:

```json
{
  "status": "validation_failed",
  "error_code": "validation.missing_file",
  "message": "Required file signal.bin is missing",
  "details": { "file": "signal.bin" }
}
```

Полный список `error_code` — в
[reference/experiment_package.md](../reference/experiment_package.md). Коды —
часть API contract; UI может использовать их для локализованных сообщений.

---

## Отчёт валидации

Для каждого run сохраняется JSON-report. Для accepted:

```text
/srv/complex_eeg/experiments/{experiment_id}/validation/validation_report.json
```

Для непринятых — во временной директории session:

```text
/srv/complex_eeg/upload_tmp/{upload_session_id}/validation_report.json
```

Cleanup failed sessions удаляет report вместе с временной директорией после
retention window. В PostgreSQL для accepted хранится `validation_report_path`;
для failed sessions path вычисляется из `upload_session_id`.

---

## Интеграция со статусами

```text
uploaded -> validating
validating -> accepted
validating -> validation_failed
```

При `accepted` сервер переносит/загружает source files в bronze, обновляет
`experiments`, пишет `experiment_events` и запускает primary pipeline run.
При `validation_failed` сохраняет `error_code` и message, не принимает пакет и
не запускает pipeline.

---

## Тесты

Минимальный набор: отсутствие `signal.bin` / `experiment.json`, битый JSON,
несовпадение и неверный формат `experiment_id`, пустой сигнал, размер не кратен
4, сегмент вне границ, пересечение сегментов, метка на несуществующий сегмент,
валидный минимальный пакет принят, дубль accepted отклонён.
