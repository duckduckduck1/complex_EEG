# Формат пакета эксперимента

Контракт между Flutter-приложением оператора и сервером: приложение создаёт пакет
эксперимента, сервер принимает его при загрузке через веб-кабинет.

**Источник истины — серверный валидатор**
[`package_validator.py`](../../server/app/features/validation/package_validator.py).
Приложение валидирует пакет локально для быстрой обратной связи, но финальную
проверку делает сервер. Правила ниже должны совпадать с валидатором.

## Состав пакета

Обязательные файлы:

```text
experiment_folder/
  signal.bin
  experiment.json
```

Опциональные:

```text
  journal.ndjson
  app.log
```

## signal.bin

- Отсчёт: `int32`, little-endian.
- Единица амплитуды: микровольты.
- Частота дискретизации: 250 Гц.
- Файл содержит только значения амплитуды; время, сегменты, метки и ФБМ — в JSON.
- `sample_count = размер_файла_в_байтах / 4`.

Сервер требует: файл существует, не пустой, размер кратен 4 байтам.

## experiment.json

Корень — JSON-объект в UTF-8.

### Поля, которые проверяет сервер (обязательные)

| Поле | Правило |
|------|---------|
| `experiment_id` | строка, regex `^[a-zA-Z0-9_-]{1,64}$`; должен совпадать с `experiment_id` сессии загрузки |
| `metadata` | объект; может быть пустым `{}`, но поле обязано присутствовать |
| `segments` | непустой массив сегментов (правила ниже) |

### Рекомендуемые поля (приложение пишет, сервер не требует)

`display_name`; `recording` (`sample_rate_hz`, `adc`, `amplitude_unit`,
`sample_encoding`); `gaps`; `segments[].started_at_wall_clock`. Сервер их не
валидирует, но они нужны для воспроизводимости.

### Пример

```json
{
  "experiment_id": "exp_01HX7M8M9RF2K0Z6GNZ6D7Q7AP",
  "display_name": "exp1",
  "metadata": { "animal_id": "mouse_1" },
  "recording": {
    "sample_rate_hz": 250,
    "adc": "MAX30003",
    "amplitude_unit": "microvolts",
    "sample_encoding": "int32_le"
  },
  "segments": [
    { "segment_id": "seg_1", "start_sample": 0, "end_sample": 1000,
      "started_at_wall_clock": "2026-06-17T10:00:00Z" }
  ],
  "gaps": [],
  "labels": [],
  "fbm_events": []
}
```

## Сегменты

- `segment_id`: regex `^seg_[1-9][0-9]*$` (`seg_1`, `seg_2`, …).
- `start_sample` ≥ 0; `end_sample` > `start_sample`; интервал полуоткрытый
  `[start_sample, end_sample)`.
- `end_sample` ≤ `sample_count`.
- Сегменты отсортированы по `start_sample` по возрастанию и не пересекаются.
- Разрывы задаются явно (`gaps`), без синтетических отсчётов.

## Метки (`labels`) — опционально

Массив. Каждая метка ссылается на существующий `segment_id` и задаёт либо точку
`sample_index`, либо интервал `start_sample`/`end_sample`. Точка или интервал
должны полностью лежать внутри своего сегмента.

## ФБМ-события (`fbm_events`) — опционально

Массив. Каждое событие фотобиомодуляции ссылается на существующий `segment_id` и
`sample_index` внутри этого сегмента.

## journal.ndjson — опционально

Append-only, одна строка — один JSON-объект. Типы событий: `experiment_started`,
`segment_started`, `segment_ended`, `connection_lost`, `connection_resumed`,
`annotation_created`, `annotation_updated`, `annotation_deleted`, `fbm_event`,
`recording_stopped`, `recovery_performed`. Финальный `experiment.json` собирается
из журнала и реального размера `signal.bin`.

## app.log — опционально

Технические диагностические записи (ошибки BLE, записи файлов, восстановление,
экспорт, исключения). Не является источником научной истины.

## Коды ошибок валидации

Сервер возвращает машиночитаемые коды:
`validation.missing_file`, `validation.signal_empty`,
`validation.signal_size_invalid`, `validation.json_parse_failed`,
`validation.required_field_missing`, `validation.experiment_id_invalid`,
`validation.experiment_id_mismatch`, `validation.segment_invalid_range`,
`validation.segment_out_of_bounds`, `validation.segment_overlap`,
`validation.label_unknown_segment`, `validation.label_out_of_bounds`,
`validation.fbm_event_out_of_bounds`.

## Связанное

- [ADR 0001 — EEG-only MVP scope](../decisions/0001-eeg-only-mvp-scope.md)
- [ADR 0002 — MinIO bronze storage](../decisions/0002-eeg-minio-bronze-storage.md)
- Дизайн приложения: `docs/flutter_app/` (recording, annotation, recovery).
