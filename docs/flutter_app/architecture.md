# Архитектура приложения

Документ описывает структуру Flutter-кода, границы слоёв и правила зависимостей.

---

## Цель

Приложение должно надёжно записывать ЭЭГ локально, отображать live-сигнал,
позволять разметку, сохранять самодостаточный эксперимент и готовить package для
последующей ручной загрузки через Web UI сервера.

Ни один экран не должен напрямую работать с BLE, файловой системой,
локальной БД или внешними интеграциями. Всё проходит через BLoC и слой
сервисов/repositories.

---

## Слои

```text
presentation
  screens
  widgets
  blocs

application
  use_cases
  coordinators
  dto

domain
  entities
  value_objects
  failures
  policies

data
  repositories
  local_data_sources
  remote_data_sources
  mappers

platform
  ble
  filesystem
  disk
  clock
```

Правило зависимостей:

```text
presentation -> application -> domain
data -> domain
platform -> data
```

UI не зависит от platform layer.

---

## Целевая структура проекта

```text
flutter_app/
  lib/
    main.dart
    app/
      app.dart
      router.dart
      app_bloc_observer.dart
      dependency_scope.dart
    core/
      config/
      errors/
      logging/
      time/
      ids/
      result/
    features/
      devices/
        presentation/
          blocs/
          screens/
          widgets/
        application/
        domain/
        data/
      recording/
      annotation/
      experiments/
      visualization/
      utilities/
      package_handoff/
      settings/
    platform/
      ble/
      file_system/
      disk_space/
```

Каждый feature имеет собственные `presentation/application/domain/data`.
Общие примитивы лежат в `core`.

---

## Идентификаторы

### `experiment_id`

Формат совместим с сервером:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Решение первого стенда:

```text
experiment_id = exp_<ULID>
```

Пример:

```text
exp_01HX7M8M9RF2K0Z6GNZ6D7Q7AP
```

Пользовательское имя папки не является `experiment_id`. Оно хранится как
`display_name` и может быть изменено без изменения технического ID.

### `device_session_id`

Локальный ID активной записи конкретного BLE-устройства. Используется только
внутри приложения для связывания BLoC instances и writer.

---

## Dependency injection

Зависимости создаются в `dependency_scope.dart`.

UI получает только:

- BLoC/Cubit;
- readonly view models;
- callbacks, которые dispatch events.

Пример:

```dart
MultiRepositoryProvider(
  providers: [
    RepositoryProvider<DeviceRepository>(create: (_) => BleDeviceRepository(...)),
    RepositoryProvider<ExperimentRepository>(create: (_) => LocalExperimentRepository(...)),
    RepositoryProvider<PackageExportRepository>(create: (_) => LocalPackageExportRepository(...)),
  ],
  child: MultiBlocProvider(...),
)
```

---

## Навигация

Navigation layer не выполняет бизнес-операции.

Разрешено:

- открыть экран;
- передать `experiment_id`;
- создать scoped BLoC для экрана;
- закрыть диалог и вернуть пользовательский выбор.

Запрещено:

- стартовать запись из route callback;
- писать файлы из screen;
- выполнять внешние интеграции из widget;
- менять статус эксперимента вне BLoC/use case.

---

## Feature boundaries

### `devices`

Discovery, remembered devices, connection status, reconnect command.

### `recording`

Start/stop, buffers, sample conversion, segment lifecycle, writer coordination.

### `annotation`

State labels, point events, bad/exclude regions, dictionary management.

### `experiments`

Saved experiments list, local status, open saved experiment, finalization.

### `visualization`

Live chart and saved experiment chart.

### `utilities`

Frequency spectrum, band power, spectrogram, filter preview, diagnostic logs.

### `package_handoff`

Package validation, optional `.zip` export, and handoff instructions for Web UI
upload. This feature does not perform HTTP upload in MVP.

---

## Multi-device UI

Основной экран показывает список подключённых и ранее известных устройств.

UI model первого стенда:

```text
left/sidebar: devices and connection status
main area: tabs/panels for active device experiments
```

Каждый active experiment tab создаёт собственный `DeviceExperimentScope` с BLoC
instances. Пользователь может переключаться между вкладками, но остановка или
закрытие активной записи требует явного действия.

Модель вкладок:

- одна вкладка — одно устройство и его эксперимент; вкладки независимы;
- набор BLoC вкладки создаётся один раз при её открытии и живёт до закрытия —
  переключение между вкладками не пересоздаёт state и не прерывает запись;
- состояние вкладки (выбранные настройки, viewport графика, фильтры) сохраняется
  при уходе на другую вкладку и при возврате; контент вкладок не размонтируется
  при переключении;
- закрытие вкладки с активной записью требует подтверждения и корректного
  завершения сегмента;
- нельзя закрыть последнюю вкладку — всегда остаётся хотя бы одна рабочая область.

---

## Error handling

Domain errors are typed:

```text
BleFailure
RecordingFailure
StorageFailure
ValidationFailure
PackageExportFailure
RecoveryFailure
```

BLoC state exposes user-safe error messages and technical error codes. Stack
traces and raw exceptions are written only to app logs.

---

## Logging

Application logs go to:

```text
{app_data}/logs/app.log
```

Experiment events go to:

```text
{experiment_dir}/journal.ndjson
```

These are different streams. `app.log` is diagnostic; `journal.ndjson` is part of
the experiment source.

---

## Проверки реализации

- no production screen uses repository directly;
- every feature screen is backed by BLoC/Cubit;
- file/BLE/external integration calls are absent from widgets;
- experiment IDs pass server regex;
- each active device has isolated recording state;
- BLoC tests cover main state transitions.
