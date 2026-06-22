# Управление состоянием (Bloc)

## Статус

Draft.

Документ фиксирует обязательные правила BLoC для Flutter-приложения.

---

## Главный принцип

Весь сценарный state приложения находится в BLoC/Cubit.

Widget tree:

- подписывается на состояние через `BlocBuilder`, `BlocSelector`,
  `BlocListener`;
- отправляет события через `context.read<XBloc>().add(...)`;
- не вызывает repositories/services напрямую;
- не хранит бизнес-состояние в `StatefulWidget`.

---

## Типы BLoC

### App-level

```text
AppBloc
SettingsCubit
ExperimentIndexBloc
LabelDictionaryCubit
```

Живут всё время работы приложения.

`LabelDictionaryCubit` является app-level singleton, потому что справочник меток
используется и в settings screen для редактирования, и в annotation screen для
разметки. Экранные scopes не создают отдельные экземпляры справочника.

### Device-level

```text
DeviceDiscoveryBloc
DeviceConnectionBloc
RememberedDevicesBloc
```

Discovery может быть singleton. Connection создаётся per device.

### Recording session-level

```text
RecordingBloc
SignalBufferCubit
SegmentBloc
QualityBloc
PhotobiomodulationBloc
DiskSpaceCubit
```

Создаются на активный эксперимент устройства и уничтожаются после закрытия
recording session.

### Editor/viewer-level

```text
ExperimentViewerBloc
AnnotationBloc
AnnotationEditorCubit
VisualizationBloc
UtilitiesBloc
```

Создаются при открытии сохранённого или live эксперимента.

### Settings-level

```text
MetadataFormBloc
StorageSettingsCubit
PackageExportSettingsCubit
```

Создаются на время открытия settings/metadata screens. `MetadataFormBloc` также
используется перед стартом записи, когда пользователь заполняет форму
эксперимента.

### Experiments-list-level

```text
ExperimentListFilterCubit
ExperimentActionsBloc
```

Создаются на время открытия списка сохранённых экспериментов.

### Startup/recovery-level

```text
RecoveryBloc
```

Создаётся при startup scan, если приложение нашло незавершённые или
повреждённые локальные эксперименты.

### Package handoff

```text
ExperimentPackageValidationCubit
PackageExportBloc
```

Создаются при проверке/экспорте готового experiment package. В MVP эти BLoC не
выполняют HTTP upload и не хранят server auth token.

---

## Запрещено

- `setState` для recording status, BLE status, package export status, annotation,
  selected experiment, chart window, utility params;
- прямой вызов `File(...)` из widget;
- прямой вызов HTTP client из widget/BLoC presentation helpers;
- direct BLE subscription inside widget;
- mutable global singleton для активной записи.

---

## Допустимо

`setState` допустим только для локальных визуальных эффектов:

- hover;
- раскрытие tooltip;
- временная анимация;
- focus highlight.

Если значение должно пережить rebuild, влиять на данные или использоваться
другим widget — это BLoC/Cubit state.

---

## Event naming

Events are past-tense user/system facts or commands:

```text
RecordingStartRequested
RecordingStopRequested
BlePacketReceived
ConnectionLost
ManualReconnectRequested
StateLabelStarted
StateLabelEnded
PackageValidationRequested
PackageExportRequested
```

Не использовать vague events:

```text
Update
Change
DoStuff
```

---

## State naming

State содержит всё, что нужно UI для отображения.

Пример:

```dart
final class RecordingState {
  final RecordingStatus status;
  final ExperimentId experimentId;
  final int savedSampleCount;
  final int bufferedSampleCount;
  final List<SegmentView> segments;
  final RecordingFailure? lastError;
}
```

State immutable. Изменения только через `copyWith` или generated immutable
classes.

---

## Side effects

Side effects выполняются в use cases/services, вызванных из BLoC.

Пример:

```text
RecordingBloc
  -> StartRecordingUseCase
    -> ExperimentRepository
    -> SignalWriter
```

BLoC отвечает за orchestration and state. Writer отвечает за запись bytes.

---

## Streams

BLE data stream is high-frequency. UI не должен получать каждую точку как новый
full app state.

Правило:

- writer получает все samples;
- chart buffer получает decimated/windowed view;
- UI получает throttled chart state;
- critical events пишутся без throttle.

---

## Multi-device isolation

Для каждого подключённого устройства создаётся независимый scope:

```text
DeviceExperimentScope
  RecordingBloc
  SignalBufferCubit
  SegmentBloc
  AnnotationBloc
  AnnotationEditorCubit
  QualityBloc
  PhotobiomodulationBloc
  DiskSpaceCubit
```

UI model for multi-device:

- main screen shows connected/remembered devices as a device list;
- every active recording opens a tab/panel keyed by `device_session_id`;
- each tab owns its `DeviceExperimentScope`;
- closing a tab requires explicit stop/finalize/cancel decision if recording is
  active.

Ошибка одного scope не меняет состояние другого scope.

---

## BLoC tests

Каждый BLoC должен иметь тесты:

- initial state;
- happy path;
- failure path;
- cancellation/dispose;
- repeated event safety;
- no duplicate side effects.

Для BLoC, который пишет данные, тест проверяет не только state, но и вызовы
use case/repository mock.
