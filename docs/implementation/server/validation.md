# validation.md

## Статус

Draft.

Документ описывает реализацию валидатора пакета эксперимента.

---

## Назначение

Валидатор проверяет, что загруженный пакет можно принять сервером и передать в
обработку. Валидатор не исправляет исходные файлы.

---

## Вход

Валидатор получает:

```text
upload_session_id
experiment_id
tmp_path
signal.bin
experiment.json
journal.ndjson optional
app.log optional
```

Валидация запускается после `complete upload`.

---

## Формат `experiment_id`

Допустимый формат:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Проверка выполняется:

1. при создании upload session;
2. при чтении `experiment.json`;
3. перед построением permanent filesystem path.

Если `experiment_id` в `experiment.json` не соответствует regex или не совпадает
с upload session, валидация завершается ошибкой.

---

## Минимальная схема `experiment.json`

Минимальный валидный документ первого стенда:

```json
{
  "experiment_id": "exp_2026_001",
  "metadata": {},
  "segments": [
    {
      "segment_id": "seg_1",
      "start_sample": 0,
      "end_sample": 1000
    }
  ]
}
```

Required fields:

```text
experiment_id: string, regex ^[a-zA-Z0-9_-]{1,64}$
segments: non-empty array
segments[].segment_id: string, non-empty
segments[].start_sample: integer >= 0
segments[].end_sample: integer > start_sample
```

Optional first-stage fields:

```text
metadata: object
sample_rate_hz: number > 0
gaps: array
labels: array
fbm_events: array
```

`metadata` сохраняется в `experiments.metadata_json` как есть. Полный
`experiment.json` хранится как исходный файл.

---

## Выход

Successful result:

```json
{
  "status": "accepted",
  "experiment_id": "exp_2026_001",
  "metadata": {},
  "storage_bucket": "lakehouse-bronze",
  "storage_prefix": "eeg/exp_2026_001/"
}
```

Failed result:

```json
{
  "status": "validation_failed",
  "error_code": "validation.missing_file",
  "message": "Required file signal.bin is missing",
  "details": {
    "file": "signal.bin"
  }
}
```

---

## Проверки

### Required files

- `signal.bin` exists;
- `experiment.json` exists;
- files are regular files;
- files are readable;
- files are not zero-sized, except optional logs.

### JSON

- `experiment.json` parses as UTF-8 JSON;
- root value is object;
- required fields from the minimal schema exist;
- `experiment_id` in JSON matches upload session;
- numeric fields have valid types.

### Duplicate protection

Валидатор и upload service выполняют повторную защитную проверку:

- нет already accepted experiment with same `experiment_id`;
- upload session still belongs to this `experiment_id`;
- session was not cancelled or expired.

Основная проверка дублей выполняется при создании upload session, но повторная
проверка защищает от гонок и ручных повреждений состояния.

DB-level защита:

- `experiments.experiment_id` unique защищает accepted experiments;
- partial unique index на active `upload_sessions(experiment_id)` запрещает две
  активные upload sessions для одного experiment;
- `complete` берёт row-level lock на строку `upload_sessions` через
  `SELECT ... FOR UPDATE`.

### Binary signal

- `signal.bin` size > 0;
- file size divisible by 4;
- sample count = `file_size / 4`;
- sample count >= `max(segment.end_sample for segment in segments)`;
- binary format is int32 amplitudes in microvolts.

### Segments

- every segment has `segment_id`;
- `start_sample >= 0`;
- `end_sample <= sample_count`;
- `start_sample < end_sample`;
- intervals are `[start_sample, end_sample)`;
- segments do not overlap;
- segments are sorted by `start_sample` ascending.

Если порядок сегментов нарушен, валидатор возвращает
`validation.segment_invalid_range`.

### Gaps

- gap references existing adjacent segments;
- gap duration, if present, is non-negative;
- validator does not synthesize missing samples.

### Labels and events

- label references existing segment;
- point event sample index is inside segment;
- interval label stays inside segment;
- FBM event references existing segment/sample;
- optional fields are type-checked.

---

## Error codes

Initial error codes:

```text
validation.missing_file
validation.json_parse_failed
validation.required_field_missing
validation.experiment_id_invalid
validation.experiment_id_mismatch
validation.experiment_already_accepted
validation.signal_empty
validation.signal_size_invalid
validation.segment_out_of_bounds
validation.segment_invalid_range
validation.segment_overlap
validation.label_unknown_segment
validation.label_out_of_bounds
validation.fbm_event_out_of_bounds
validation.internal_error
```

Коды являются частью API contract. UI может использовать их для локализованных
сообщений.

---

## Отчёт валидации

Для каждого validation run сохраняется JSON report:

```text
/srv/complex_eeg/experiments/{experiment_id}/validation/validation_report.json
```

Минимальное содержимое:

```json
{
  "experiment_id": "exp_2026_001",
  "status": "accepted",
  "checked_at": "2026-06-17T10:05:00Z",
  "signal_size_bytes": 1000000,
  "sample_count": 250000,
  "warnings": [],
  "errors": []
}
```

Если эксперимент не принят, report хранится в:

```text
/srv/complex_eeg/upload_tmp/{upload_session_id}/validation_report.json
```

Cleanup для failed sessions удаляет этот report вместе с временной директорией
после retention window. В PostgreSQL для accepted experiments хранится
`validation_report_path`; для failed upload sessions path вычисляется из
`upload_session_id`.

---

## Интеграция со статусами

Flow:

```text
uploaded -> validating
validating -> accepted
validating -> validation_failed
```

При `accepted` сервер:

- загружает source files в MinIO bronze;
- проверяет, что MinIO отдаёт загруженные объекты;
- одной PostgreSQL transaction обновляет `upload_sessions`, `experiments`,
  `source_files`, `upload_storage_events`, `pipeline_runs` и
  `experiment_events`;
- после commit удаляет локальную `experiments/{experiment_id}/source/`;
- запускает primary pipeline run.

Если PostgreSQL commit падает после successful MinIO upload, объекты MinIO
логируются best-effort в `upload_orphan_objects` как `pending_cleanup`, а retry
`complete` снова использует source package из `upload_tmp`.

При `validation_failed` сервер:

- сохраняет `error_code`;
- сохраняет readable message;
- не переносит пакет в accepted source storage;
- не запускает pipeline.

---

## Тесты

Минимальный test suite:

- missing `signal.bin`;
- missing `experiment.json`;
- invalid JSON;
- mismatch `experiment_id`;
- invalid `experiment_id` format;
- empty signal;
- signal size not divisible by 4;
- segment out of bounds;
- segment overlap;
- label references unknown segment;
- valid minimal experiment accepted;
- duplicate accepted experiment rejected.
