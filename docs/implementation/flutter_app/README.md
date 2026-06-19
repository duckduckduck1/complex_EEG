# Flutter app implementation

## Статус

Draft.

Раздел описывает реализацию Windows Flutter-приложения для локальной записи,
разметки, диагностики и подготовки experiment package для последующей ручной
загрузки через Web UI сервера.

---

## Обязательное архитектурное правило

Во всём приложении используется BLoC.

Правило:

- UI не хранит бизнес-состояние через `setState`;
- screen state живёт в `Bloc` или `Cubit`;
- widget отправляет события и отображает состояние;
- доступ к BLE, файлам, БД, серверу и DSP идёт через repositories/services;
- один эксперимент устройства управляется отдельным набором BLoC instances.

`setState` допустим только для локальной визуальной мелочи, которая не влияет на
данные, запись, отправку, разметку, подключение или навигацию.

---

## Документы

```text
architecture.md       - структура Flutter-кода и зависимости слоёв
bloc.md               - правила BLoC, события, состояния, lifetimes
ble.md                - BLE discovery/connection/data stream
recording.md          - запись сигнала, буферы, сегменты, ФБМ, качество
storage.md            - локальное файловое хранилище и индекс экспериментов
experiment_format.md  - signal.bin, experiment.json, journal.ndjson, app.log
experiments.md        - список сохранённых экспериментов, просмотр, удаление
annotation.md         - разметка, справочник меток, доразметка
visualization.md      - график live/saved сигнала
utils.md              - спектр, мощность, спектрограмма, фильтры, логи
server_sync.md        - package handoff: проверка и экспорт пакета для Web UI
recovery.md           - восстановление после краша приложения/системы
settings.md           - настройки приложения, метаданные, справочники
testing.md            - тестовая стратегия Flutter-приложения
```

`server_sync.md` сохраняет старое имя файла, но в MVP не описывает прямую
сетевую синхронизацию. Реальная feature в коде должна называться
`package_handoff`.

---

## Базовые решения первого стенда

- Platform: Windows desktop.
- UI: Flutter.
- State management: `flutter_bloc`.
- Navigation: route layer вызывает только BLoC providers, не бизнес-логику.
- Local experiment index: embedded local DB или JSON index file, решение
  уточняется при создании кода; контракт описан в `storage.md`.
- Source of truth для эксперимента: папка эксперимента.
- Source of truth во время записи: `signal.bin` + `journal.ndjson`.
- Final export contract: `signal.bin` + `experiment.json`.
- Server handoff: manual package export; upload выполняется через Web UI.

---

## Главные ограничения

- Сервер не нужен для записи.
- Каждое BLE-устройство ведёт независимый эксперимент.
- Разрывы BLE не склеиваются.
- `signal.bin` содержит int32 амплитуды в мкВ.
- `experiment.json` ссылается на бинарник через sample indexes.
- Все пользовательские действия, которые меняют эксперимент, пишутся в
  append-only journal.
