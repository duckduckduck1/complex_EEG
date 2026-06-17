# storage.md

## Статус

Draft.

Документ описывает локальное хранилище Flutter-приложения.

---

## Source of truth

Главный источник истины — папка эксперимента.

```text
{experiments_root}/
  {display_folder_name}/
    signal.bin
    journal.ndjson
    experiment.json
    app.log
```

Local index нужен для быстрого списка экспериментов, но эксперимент должен быть
восстановим из своей папки.

---

## App data paths

Целевые логические директории:

```text
app_data/
  config/
  logs/
  cache/
  indexes/

experiments_root/
  exp1/
  exp2/
```

Реальные Windows paths выбираются через platform file system service.

---

## Experiment folder naming

Пользователь задаёт `display_name`. Для папки оно sanitizes:

- запрещены path separators;
- запрещены reserved Windows names;
- trailing dot/space removed;
- при конфликте добавляется suffix.

Технический `experiment_id` не зависит от имени папки и хранится внутри
`experiment.json`.

---

## Local experiment index

Index record:

```text
experiment_id
display_name
folder_path
created_at
updated_at
recording_status
server_status
active_upload_session_id
sample_count
duration_seconds
has_final_json
last_error
```

Решение первого стенда:

- можно начать с JSON/SQLite-like index;
- implementation должен быть скрыт за `ExperimentIndexRepository`;
- UI не зависит от формата индекса.

---

## Repositories

```text
ExperimentRepository
ExperimentIndexRepository
JournalRepository
SignalFileRepository
SettingsRepository
LabelDictionaryRepository
```

Repository methods return domain entities or typed failures, not raw exceptions.

---

## File safety

Правила:

- `signal.bin` append-only during recording;
- `journal.ndjson` append-only;
- final `experiment.json` writes to temp file first;
- temp file is atomically renamed;
- never overwrite source files without backup/explicit user action;
- path traversal is rejected for every user-provided path/name.

---

## Server status storage

Local server status values:

```text
not_sent
queued
creating_session
uploading
upload_error
uploaded
accepted
validation_failed
processing
processed
processing_failed
cancelled
cancel_pending
expired
```

This is the canonical local upload/server status list. Other documents reference
this list instead of redefining it.

Status is stored in local index and refreshed from server by
`ExperimentServerStatusBloc`.

`active_upload_session_id` is stored in the local experiment index while upload
is active, cancelled pending, or resumable after app restart.

---

## Settings

Settings include:

```text
experiments_root
server_base_url
server_auth_token
signal_flush_interval_seconds
chart_window_seconds
default_sample_rate_hz
default_adc_model
label_dictionary_path optional
```

Secret values must not be logged.

---

## Проверки реализации

- experiment folder can be opened without local index;
- index can be rebuilt by scanning folders;
- final JSON write is atomic;
- folder names are sanitized;
- server status survives app restart;
- paths from user input cannot escape experiments root.
