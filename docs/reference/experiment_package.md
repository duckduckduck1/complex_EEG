# Формат пакета эксперимента

Что приложение оператора кладёт на диск по итогам эксперимента. Это же — контракт
с внешними потребителями: веб-лаборатория (отдельный репозиторий) принимает такой
пакет при загрузке, скрипты разбора читают его напрямую.

**Источник истины — этот документ.** Пакет порождает приложение, поэтому формат
описан здесь; исполняемый валидатор живёт на стороне лаборатории и обязан
совпадать с правилами ниже. Изменение формата — согласованное: правка этого дока
и правка валидатора идут вместе (см.
[ADR 0001](../decisions/0001-app-only-repository.md)).

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

- Файл хранит **фильтрованный** сигнал записи. Исходный raw-поток BLE в MVP не
  сохраняется.
- Отсчёт: `int32`, little-endian.
- Единица амплитуды: микровольты.
- Частота дискретизации: 250 Гц.
- Файл содержит только значения амплитуды; время, сегменты, метки и ФБМ — в JSON.
- `sample_count = размер_файла_в_байтах / 4`.
- Применённые фильтры фиксируются в `experiment.json` в поле
  `recording.filters`.

Требования: файл существует, не пустой, размер кратен 4 байтам.

## experiment.json

Корень — JSON-объект в UTF-8.

### Обязательные поля

| Поле | Правило |
|------|---------|
| `experiment_id` | строка, regex `^[a-zA-Z0-9_-]{1,64}$`; уникален в пределах оператора |
| `metadata` | объект; может быть пустым `{}`, но поле обязано присутствовать |
| `segments` | непустой массив сегментов (правила ниже) |

### Рекомендуемые поля

`display_name`; `recording` (`sample_rate_hz`, `adc`, `amplitude_unit`,
`sample_encoding`, `filters`, `pwm_level`); `gaps`;
`segments[].started_at_wall_clock`.
Строгой проверки нет, но они нужны для воспроизводимости.

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
    "sample_encoding": "int32_le",
    "filters": {
      "lp": { "enabled": true, "hz": 40.0 },
      "hp": { "enabled": true, "hz": 0.5 },
      "notch": { "enabled": false, "hz": 50.0 }
    },
    "pwm_level": 50
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
- При обрыве BLE `signal.bin` не дополняется нулями: текущий сегмент закрывается,
  а после ручного переподключения открывается следующий сегмент.

## Метки (`labels`) — опционально

Массив. Каждая метка ссылается на существующий `segment_id` и задаёт либо точку
`sample_index`, либо интервал `start_sample`/`end_sample`. Эти поля — глобальные
индексы отсчётов в `signal.bin`; точка или интервал должны полностью лежать
внутри своего сегмента. Если приложению нужна локальная координата для UI, оно
может дополнительно хранить `segment_sample_index`.

## ФБМ-события (`fbm_events`) — опционально

Массив. Каждое событие фотобиомодуляции ссылается на существующий `segment_id`.
`sample_index` — глобальный индекс отсчёта в `signal.bin`, который должен лежать
в диапазоне сегмента. Приложение также пишет `segment_sample_index`,
`global_sample_index`, `wall_clock_time`, `on`, `pwm_level`, `pwm_byte` и
`command_delivered`. Если BLE-соединение уже потеряно и авто-выключение ФБМ не
могло быть доставлено, событие фиксируется с `command_delivered: false` и
`reason: "connection_lost"`.

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

- [ADR 0001 — репозиторий только для приложения](../decisions/0001-app-only-repository.md)
- Дизайн приложения: `docs/flutter_app/` (recording, annotation, recovery).
