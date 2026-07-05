# Локальный форк flutter_blue_plus_winrt 0.0.20

Это вендоренная копия пакета `flutter_blue_plus_winrt` 0.0.20 (endorsed
Windows-реализация `flutter_blue_plus`) с единственной правкой: параллельный
`DeviceWatcher` для агрессивного BLE-сканирования на Windows.

## Зачем

«Голый» `BluetoothLEAdvertisementWatcher` планируется Windows лениво — радио
слушает эфир малую долю времени, поэтому первое обнаружение медленно
рекламирующегося устройства (наш стенд JDY-16) занимает секунды, а иногда
минуты. На стенде (лог 2026-07-05) первый advertisement-пакет JDY-16 был
доставлен только на 8.8 с, после чего Windows на ~11 с переставал доставлять
пакеты вообще (хотя рядом непрерывно рекламировала себя колонка SberBoom).

Это известная проблема WinRT-сканирования (jasongin/noble-uwp#69) с проверенным
обходом: одновременно запущенный `DeviceWatcher` над BLE Association Endpoints
заставляет Windows сканировать агрессивно. Так же ведут себя «быстрые»
системные сканеры (Bluetooth LE Explorer). Публичного API поменять scan
interval/window в WinRT нет — DeviceWatcher единственный доступный рычаг.

Прежний Dart-костыль (периодический `FlutterBluePlus.systemDevices([])`) не
помогал: в логе он мгновенно возвращал пустой кеш и на планировщик скана не
влиял. Он удалён; замена — этот форк.

## Что именно изменено (относительно upstream 0.0.20)

Все правки помечены комментарием `FORK (complex_EEG)`:

- `windows/flutter_blue_plus_winrt_plugin.h` — поле `device_watcher_`,
  объявления `StartDeviceWatcher()`/`StopDeviceWatcher()`, include
  `Windows.Devices.Enumeration.h`.
- `windows/flutter_blue_plus_winrt_plugin.cpp`:
  - `StartDeviceWatcher()`/`StopDeviceWatcher()` — создают/останавливают
    `DeviceWatcher` **по точному рецепту microsoft/BluetoothLEExplorer**:
    правильный BLE AEP ProtocolId `{bb7bb05e-5972-42b5-94fc-76eaa7084d49}` и,
    главное, непустой `requestedProperties` с `System.Devices.Aep.SignalStrength`,
    `IsPresent`, `LastSeenTime`. Именно отслеживание этих «живых» свойств
    заставляет Windows вести непрерывный активный скан; без них watcher делает
    разовую энумерацию и радио не сканирует (первая версия форка ошибочно
    передавала `nullptr` и неверный GUID — потому не помогала: release и debug
    находили устройства за 7–18 с, а BLE Explorer на той же машине — мгновенно).
    Результаты энумерации не потребляются (пустые хендлеры) — watcher нужен
    только чтобы держать радио в активном скане. Новый экземпляр на каждый
    `startScan`, чтобы избежать ошибок Start-во-время-Stopping при быстрых
    циклах стоп/старт.
  - `startScan` → дополнительно `StartDeviceWatcher()`; `stopScan` и
    `flutterRestart` → `StopDeviceWatcher()`; деструктор → `StopDeviceWatcher()`.
  - `OnAdvertisementStopped` (был пустым) → лог, чтобы молчаливую остановку
    watcher'а было видно в отладке.

Больше ничего не тронуто: connect/notify/decode/GATT — как в upstream.

## Как подключено

`flutter_app/pubspec.yaml` → `dependency_overrides: flutter_blue_plus_winrt:
path: third_party/flutter_blue_plus_winrt`. Имя пакета сохранено, поэтому
federated-резолвинг `flutter_blue_plus` подхватывает эту копию вместо
pub.dev-версии. Обновление upstream: перекопировать релиз и заново нанести
правки по меткам `FORK (complex_EEG)`.

## Апстрим

Правка `DeviceWatcher` + непустой `OnAdvertisementStopped` — кандидат на PR
в chan150/flutter_blue_plus_winrt.
