# Запись сигнала

## Статус

Draft.

Документ описывает реализацию записи эксперимента: start/stop, buffer, writer,
segments, ФБМ events и качество данных.

---

## BLoC

```text
RecordingBloc
SignalBufferCubit
SegmentBloc
QualityBloc
PhotobiomodulationBloc
DiskSpaceCubit
```

`RecordingBloc` управляет lifecycle записи. Остальные BLoC/Cubit отвечают за
узкие представления состояния.

---

## Recording lifecycle

```text
idle
preparing
recording
paused_by_disconnect
stopping
stopped
failed
recovering
```

Разрешённые переходы:

```text
idle -> preparing -> recording
recording -> paused_by_disconnect
paused_by_disconnect -> recording
recording -> stopping -> stopped
paused_by_disconnect -> stopping -> stopped
any -> failed
failed -> recovering
recovering -> recording | stopped
```

---

## Start recording

Start sequence:

1. пользователь заполняет metadata form;
2. приложение генерирует `experiment_id = exp_<ULID>`;
3. создаёт папку эксперимента;
4. создаёт пустой `signal.bin`;
5. создаёт `journal.ndjson`;
6. пишет событие `experiment_started`;
7. открывает первый segment;
8. переводит state в `recording`.

Если любой шаг падает, запись не считается начатой.

---

## Signal writer

`signal.bin` содержит последовательность int32 little-endian значений амплитуды в
мкВ.

Writer policy:

```text
append-only
flush interval: 10 seconds
configurable
```

Signal samples:

1. приходят из BLE decoder;
2. помещаются в in-memory write buffer;
3. каждые 10 секунд batch пишется в `signal.bin`;
4. chart читает из memory buffer, не с диска.

При normal stop writer выполняет final flush.

---

## Journal writer

`journal.ndjson` пишется append-only.

Critical events sync immediately:

```text
experiment_started
segment_started
segment_ended
connection_lost
connection_resumed
recording_stopped
fbm_event
annotation_created
annotation_updated
annotation_deleted
```

Critical boundary events выполняют flush/sync.

---

## Segments

Segment = непрерывный участок сигнала между BLE disconnects.

Поля segment:

```text
segment_id
start_sample
end_sample
started_at_wall_clock
ended_at_wall_clock optional
```

`segment_id` генерируется приложением как `seg_<N>`, где `N` — порядковый номер
сегмента внутри эксперимента, начиная с 1.

Диапазон:

```text
[start_sample, end_sample)
```

`start_sample` и `end_sample` — global sample indexes in `signal.bin`.

Разметка использует:

```text
segment_id + segment_sample_index
```

---

## Disconnect handling

При BLE disconnect:

1. writer flushes current buffer;
2. current segment closes at last saved/buffered sample boundary;
3. `connection_lost` event writes to journal;
4. state becomes `paused_by_disconnect`;
5. ФБМ command disabled;
6. chart shows explicit gap.

Signal during disconnect is absent and never synthesized.

---

## Manual reconnect

Reconnect is user-triggered.

После reconnect:

1. new segment starts;
2. approximate gap duration is calculated by wall clock;
3. `connection_resumed` and `segment_started` events write to journal;
4. samples append to the same `signal.bin`.

---

## Photobiomodulation

ФБМ команда доступна только в `recording`.

When triggered:

1. `PhotobiomodulationBloc` validates recording status;
2. BLE command is sent;
3. event is written to `journal.ndjson` immediately;
4. UI shows command result.

Event fields:

```text
segment_id
segment_sample_index
global_sample_index
wall_clock_time
duration_ms optional
intensity optional
```

---

## Quality control

`QualityBloc` computes live indicators from memory buffer:

- signal present/absent;
- amplitude range;
- clipping/saturation suspicion;
- flatline suspicion;
- packet decode errors;
- disconnect state.

Quality warnings do not modify `signal.bin`. If user marks bad region, it is an
annotation event.

---

## Disk space

`DiskSpaceCubit` checks free space:

- before start;
- periodically during recording;
- before finalization.

If threshold is low:

- UI warns user;
- recording may continue until critical threshold;
- critical threshold prevents new recording start.

---

## Large files

Явного лимита на размер `signal.bin` в приложении не задаётся. При 250 sps и
int32 размер растёт примерно на 1 KB/s, поэтому многочасовые эксперименты могут
быть большими.

Требования:

- `DiskSpaceCubit` предотвращает заполнение диска;
- сохранённый эксперимент читается lazy/chunked, не целиком в память;
- chart reader читает только viewport range;
- utilities получают выбранное окно, а не весь файл.

---

## Stop recording

Stop sequence:

1. stop accepting new samples;
2. final flush signal buffer;
3. close active segment;
4. write `recording_stopped`;
5. build final `experiment.json`;
6. update local experiment index;
7. state becomes `stopped`.

---

## Проверки реализации

- samples are written as int32 little-endian;
- writer flushes every configured interval;
- journal writes critical events immediately;
- disconnect closes segment;
- reconnect opens new segment;
- ФБМ disabled in `paused_by_disconnect`;
- stop creates final `experiment.json`;
- two devices write two independent experiment folders.
