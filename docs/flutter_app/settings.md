# Настройки

## Статус

Draft.

Документ описывает настройки приложения, форму метаданных эксперимента и
настраиваемые справочники.

---

## BLoC

```text
SettingsCubit
MetadataFormBloc
StorageSettingsCubit
PackageExportSettingsCubit
```

Настройки не читаются напрямую из widget. UI показывает state и dispatch events.
Settings screen использует app-level singleton `LabelDictionaryCubit` для
редактирования справочника меток и не создаёт отдельный экземпляр.

---

## App settings

Поля:

```text
experiments_root
signal_flush_interval_seconds
chart_window_seconds
default_sample_rate_hz
default_adc_model
label_dictionary_path optional
```

Default values:

```text
sample_rate_hz = 250
adc_model = MAX30003
signal_flush_interval_seconds = 10
```

---

## Metadata form

Перед стартом записи пользователь заполняет metadata form.

Минимальные поля:

```text
display_name
animal_id
operator
experiment_goal
conditions
notes optional
```

Автоматически добавляются:

```text
experiment_id = exp_<ULID>
created_at
sample_rate_hz = 250
adc_model = MAX30003
amplitude_unit = microvolts
sample_encoding = int32_le
app_version
```

`app_version` берётся из package metadata через `package_info_plus`
(`PackageInfo.version` + build number, если доступен).

Metadata form не стартует запись напрямую. Она dispatches
`RecordingStartRequested` with validated metadata.

---

## Validation

Rules:

- `display_name` не пустой;
- `experiment_id` генерируется приложением и matches `^[a-zA-Z0-9_-]{1,64}$`;
- `sample_rate_hz` fixed to 250 on first stand;
- required metadata fields must be present before recording starts;
- filesystem folder name is sanitized separately from `display_name`.

---

## Label dictionary settings

Dictionary is editable:

```text
label_type_id
kind
display_name
color
is_active
sort_order
```

Rules:

- deleting label type used by old experiments marks it inactive;
- old experiments keep rendering inactive labels;
- dictionary changes do not rewrite old `signal.bin`;
- dictionary export/import is allowed as JSON.

---

## Package export settings

Package export settings:

```text
default_export_directory optional
zip_export_enabled
include_app_log_by_default
```

Flutter-приложение не хранит server auth token в MVP. Загрузка пакета
выполняется через Web UI после web-аутентификации пользователя.

---

## Storage settings

Changing `experiments_root`:

1. user selects new directory;
2. app validates access;
3. app offers scan/rebuild index;
4. setting is saved only after successful validation.

App does not silently move existing experiments unless user explicitly chooses
archive/move action.

---

## Проверки реализации

- metadata cannot start recording while invalid;
- generated experiment ID matches server regex;
- package export settings do not contain server credentials;
- changing experiments root validates directory access;
- inactive labels still render old experiments;
- settings state is managed by Cubit/BLoC, not widget local state.
