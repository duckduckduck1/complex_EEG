# experiment_format.md

## Статус

Draft.

Документ фиксирует локальный формат файла эксперимента, который приложение
создаёт и отправляет на сервер.

---

## Folder layout

Минимально:

```text
experiment_folder/
  signal.bin
  experiment.json
```

Дополнительно:

```text
experiment_folder/
  journal.ndjson
  app.log
```

---

## `signal.bin`

Binary format:

```text
int32 little-endian
unit: microvolts
sample_rate_hz: 250
```

Файл содержит только значения амплитуды. Время, сегменты, разрывы, метки и ФБМ
events хранятся в JSON/journal.

Sample count:

```text
sample_count = file_size_bytes / 4
```

Если размер не делится на 4, файл повреждён.

---

## `experiment_id`

Формат:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Решение приложения:

```text
exp_<ULID>
```

Этот ID передаётся серверу и используется для защиты от дублей.

---

## Minimal `experiment.json`

```json
{
  "experiment_id": "exp_01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
  "display_name": "exp1",
  "metadata": {},
  "recording": {
    "sample_rate_hz": 250,
    "adc": "MAX30003",
    "amplitude_unit": "microvolts",
    "sample_encoding": "int32_le"
  },
  "segments": [
    {
      "segment_id": "seg_1",
      "start_sample": 0,
      "end_sample": 1000,
      "started_at_wall_clock": "2026-06-17T10:00:00Z"
    }
  ],
  "gaps": [],
  "labels": [],
  "fbm_events": []
}
```

Required for server compatibility:

```text
experiment_id
metadata
segments[]
segments[].segment_id
segments[].start_sample
segments[].end_sample
```

`metadata` may be an empty object `{}`, but the field must be present.

---

## Segments

`segment_id` format:

```text
seg_<N>
```

`N` is the segment ordinal inside one experiment, starting from 1.

Examples:

```text
seg_1
seg_2
seg_3
```

Segments are sorted by `start_sample` ascending.

Rules:

- `start_sample >= 0`;
- `end_sample > start_sample`;
- intervals are `[start_sample, end_sample)`;
- segments do not overlap;
- gaps are represented explicitly, not by synthetic samples.

---

## Journal format

`journal.ndjson` is append-only.

One line = one JSON object:

```json
{"type":"segment_started","segment_id":"seg_1","global_sample_index":0,"created_at":"2026-06-17T10:00:00Z"}
```

Journal event types:

```text
experiment_started
segment_started
segment_ended
connection_lost
connection_resumed
annotation_created
annotation_updated
annotation_deleted
fbm_event
recording_stopped
recovery_performed
```

Final `experiment.json` is built from journal plus actual `signal.bin` size.

---

## App log

`app.log` contains technical diagnostics:

- BLE errors;
- file write errors;
- recovery actions;
- upload errors;
- unexpected exceptions.

`app.log` is not source of scientific truth.

---

## Validation before upload

Before upload, app validates:

- required files exist;
- `experiment_id` matches regex;
- `signal.bin` size divisible by 4;
- all segments fit inside sample count;
- labels fit inside their segment;
- ФБМ events fit inside their segment.

The server repeats validation. Client-side validation is for fast feedback only.
