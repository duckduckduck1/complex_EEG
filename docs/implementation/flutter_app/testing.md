# testing.md

## Статус

Draft.

Документ описывает тестовую стратегию Flutter-приложения.

---

## Цель

Проверить не внешний вид сам по себе, а надёжность записи, разметки,
восстановления и подготовки experiment package.

---

## Test levels

### Unit tests

- ID generation;
- sample decoder;
- signal writer byte encoding;
- journal parser/replayer;
- experiment JSON builder;
- segment policies;
- annotation validation;
- package preflight validation.

### BLoC tests

Для каждого BLoC:

- initial state;
- happy path;
- failure path;
- cancellation/dispose;
- repeated event safety.

### Repository tests

- file writes are atomic;
- index rebuild from folders;
- package export repository creates safe exports;
- settings repository does not store server credentials in MVP.

### Widget tests

- screen reacts to BLoC state;
- buttons dispatch events;
- errors render user-safe messages;
- no widget directly performs file/BLE/HTTP work.

### Integration tests

- start/stop recording with fake BLE stream;
- disconnect/reconnect creates segments;
- crash recovery from synthetic journal;
- package export and validation flow;
- saved experiment annotation flow.

---

## Fakes

Required fakes:

```text
FakeBleDevice
FakeBlePacketStream
FakeFileSystem
FakeClock
FakeDiskSpaceService
FakePackageExportService
```

Fake clock is required for deterministic segment and gap tests.

---

## Golden tests

Golden tests are useful for:

- chart with gap;
- annotation overlays;
- package status badges;
- recovery dialog.

Golden tests are not a replacement for BLoC and domain tests.

---

## Critical scenarios

Must pass before first field use:

- 1 hour fake recording produces expected file size;
- BLE disconnect closes segment and does not synthesize samples;
- app restart recovers unfinished experiment;
- annotation cannot cross segment boundary;
- package validation/export works after app restart;
- two fake devices write isolated experiments.

---

## CI

Future Flutter CI should run:

```text
flutter analyze
flutter test
dart format --set-exit-if-changed
```

When integration tests become stable, they are added as a separate CI job.
