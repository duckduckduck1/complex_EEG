# Управление состоянием (Bloc)

Документ фиксирует обязательные правила BLoC для Flutter-приложения.

---

## Главный принцип

Всё сценарное состояние приложения находится в BLoC/Cubit.

Дерево виджетов:

- подписывается на состояние через `BlocBuilder`, `BlocSelector`,
  `BlocListener`;
- отправляет события через `context.read<XBloc>().add(...)`;
- не вызывает репозитории/сервисы напрямую;
- не хранит бизнес-состояние в `StatefulWidget`.

---

## Типы BLoC

### Уровень приложения

```text
AppBloc
SettingsCubit
ExperimentIndexBloc
LabelDictionaryCubit
```

Живут всё время работы приложения.

`LabelDictionaryCubit` является app-level singleton, потому что справочник меток
используется и в экране настроек для редактирования, и в экране разметки. Экранные
области (scopes) не создают отдельные экземпляры справочника.

### Уровень устройства

```text
DeviceDiscoveryBloc
DeviceConnectionBloc
RememberedDevicesBloc
```

Поиск устройств может быть singleton; подключение создаётся на каждое устройство.

### Уровень сессии записи

```text
RecordingBloc
SignalBufferCubit
SegmentBloc
QualityBloc
PhotobiomodulationBloc
DiskSpaceCubit
```

Создаются на активный эксперимент устройства и уничтожаются после закрытия сессии
записи.

### Уровень редактора/просмотра

```text
ExperimentViewerBloc
AnnotationBloc
AnnotationEditorCubit
VisualizationBloc
UtilitiesBloc
```

Создаются при открытии сохранённого или живого эксперимента.

### Уровень настроек

```text
MetadataFormBloc
StorageSettingsCubit
PackageExportSettingsCubit
```

Создаются на время открытия экранов настроек и метаданных. `MetadataFormBloc`
также используется перед стартом записи, когда пользователь заполняет форму
эксперимента.

### Уровень списка экспериментов

```text
ExperimentListFilterCubit
ExperimentActionsBloc
```

Создаются на время открытия списка сохранённых экспериментов.

### Уровень запуска/восстановления

```text
RecoveryBloc
```

Создаётся при стартовом сканировании, если приложение нашло незавершённые или
повреждённые локальные эксперименты.

### Передача пакета

```text
ExperimentPackageValidationCubit
PackageExportBloc
```

Создаются при проверке/экспорте готового пакета эксперимента. В MVP эти BLoC не
выполняют HTTP-загрузку и не хранят серверный токен авторизации.

---

## Запрещено

- `setState` для статуса записи, статуса BLE, статуса экспорта пакета, разметки,
  выбранного эксперимента, окна графика, параметров утилит;
- прямой вызов `File(...)` из виджета;
- прямой вызов HTTP-клиента из виджета или presentation-хелперов BLoC;
- прямая подписка на BLE внутри виджета;
- изменяемый глобальный singleton для активной записи.

---

## Допустимо

`setState` допустим только для локальных визуальных эффектов:

- наведение (hover);
- раскрытие подсказки (tooltip);
- временная анимация;
- подсветка фокуса.

Если значение должно пережить перестройку виджета (rebuild), влиять на данные или
использоваться другим виджетом — это состояние BLoC/Cubit.

---

## Именование событий

Событие — это факт от пользователя или системы в прошедшем времени либо команда:

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

Не использовать размытые имена событий:

```text
Update
Change
DoStuff
```

---

## Именование состояния

Состояние содержит всё, что нужно UI для отображения.

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

Состояние неизменяемо. Изменения только через `copyWith` или сгенерированные
неизменяемые классы.

---

## Побочные эффекты

Побочные эффекты выполняются в use case/сервисах, вызванных из BLoC.

Пример:

```text
RecordingBloc
  -> StartRecordingUseCase
    -> ExperimentRepository
    -> SignalWriter
```

BLoC отвечает за оркестрацию и состояние. `SignalWriter` отвечает за запись
байтов.

---

## Потоки данных

Поток данных BLE высокочастотный. UI не должен получать каждую точку как новое
полное состояние приложения.

Правило:

- `SignalWriter` получает все отсчёты;
- буфер графика получает прореженное/оконное представление;
- UI получает состояние графика с ограничением частоты обновления;
- критичные события пишутся без ограничения частоты.

---

## Изоляция нескольких устройств

Для каждого подключённого устройства создаётся независимая область (scope):

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

Модель UI для нескольких устройств:

- главный экран показывает подключённые и запомненные устройства как список;
- каждая активная запись открывает вкладку/панель с ключом `device_session_id`;
- каждая вкладка владеет своим `DeviceExperimentScope`;
- закрытие вкладки требует явного решения (остановить/финализировать/отменить),
  если запись активна.

Ошибка одной области не меняет состояние другой.

---

## Тесты BLoC

Каждый BLoC должен иметь тесты:

- начальное состояние;
- успешный сценарий;
- сбойный сценарий;
- отмена/освобождение (dispose);
- безопасность повторных событий;
- отсутствие дублирующихся побочных эффектов.

Для BLoC, который пишет данные, тест проверяет не только состояние, но и вызовы
mock-объектов use case/репозитория.
