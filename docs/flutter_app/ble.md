# BLE: связь с устройством

Документ описывает реализацию BLE-слоя приложения.

---

## Назначение

BLE-слой ищет устройства, подключается к ним, принимает пакеты сигнала и
передаёт уже распарсенные значения в recording pipeline.

Каждое устройство ведёт независимый эксперимент. Обрыв одного устройства не
останавливает запись других устройств.

---

## BLoC

```text
DeviceDiscoveryBloc
RememberedDevicesBloc
DeviceConnectionBloc
```

### `DeviceDiscoveryBloc`

Events:

```text
DiscoveryStarted
DiscoveryStopped
DeviceFound
DiscoveryFailed
```

State:

```text
idle
scanning
failed
```

### `DeviceConnectionBloc`

Events:

```text
ConnectRequested
DisconnectRequested
ConnectionEstablished
ConnectionLost
ManualReconnectRequested
ConnectionFailed
```

State:

```text
disconnected
connecting
connected
lost
reconnecting_manually
failed
```

Автоматическое переподключение не выполняется. После `ConnectionLost`
пользователь явно нажимает reconnect.

Отдельный packet-level BLoC не используется. BLE packets идут через data
source/decoder в `RecordingBloc` как событие `BlePacketReceived`, потому что
именно recording session решает, писать sample или игнорировать его.

---

## Remembered devices

Приложение хранит список ранее подключённых устройств:

```text
device_id
display_name
last_connected_at
device_model
firmware_version optional
```

Список используется для быстрого подключения без повторного discovery.

---

## Packet format

Устройство шлёт notify с потоком отсчётов по 3 байта каждый. Длина payload
кратна 3; конкретный размер пакета зависит от MTU и не фиксирован. Полный контракт
(UUID характеристики, частота, формула АЦП → мкВ, команда ФБМ) —
[формат пакета устройства](../reference/device_packet.md).

`BleSampleDecoder` разбирает payload группами по 3 байта, восстанавливает знак
18-битного значения и переводит его в микровольты. Неполный «хвост» байтов
переносится в следующий notify, чтобы не терять выравнивание потока.

Остальная часть приложения работает только с уже декодированным значением:

```text
EegSample(valueMicrovolts: int)
```

---

## Data flow

```text
BLE characteristic notification
  -> BlePacketDataSource
  -> BleSampleDecoder
  -> RecordingBloc/BlePacketReceived
  -> SignalWriter
  -> SignalBufferCubit for chart
```

BLE data source не знает про файлы эксперимента. Recording layer решает, писать
или игнорировать samples.

---

## Команда ФБМ

Управление ФБМ-светодиодом — это запись в ту же характеристику, что и приём
сигнала. `BlePacketDataSource` предоставляет исходящий метод записи кадра команды;
формат кадра — в [контракте устройства](../reference/device_packet.md).

Решение «включить/выключить/сменить яркость» принимает не BLE-слой, а
recording/annotation layer: он вызывает запись через data source и фиксирует
событие в `journal.ndjson` (и далее в `fbm_events` пакета). Так включение ФБМ
всегда привязано к активному эксперименту и попадает в его источник истины.

---

## Recording guard

Live BLE signal отображается и пишется только при активной записи.

Если устройство подключено, но запись не запущена:

- packets can be counted for diagnostics;
- signal не пишется в `signal.bin`;
- chart не показывает live stream как запись.

Это защищает от иллюзии, что эксперимент записывается.

---

## Connection loss

При обрыве:

1. `DeviceConnectionBloc` emits `lost`;
2. parent coordinator/widget with `BlocListener<DeviceConnectionBloc, ...>`
   dispatches `BleConnectionLostReceived` в scoped `RecordingBloc`;
3. текущий сегмент закрывается;
4. event пишется в `journal.ndjson` немедленно;
5. запись переводится в paused-by-disconnect;
6. UI показывает ручное reconnect action.

После ручного reconnect:

1. `BlocListener<DeviceConnectionBloc, ...>` dispatches
   `BleConnectionResumedReceived` в scoped `RecordingBloc`;
2. открывается новый сегмент;
3. wall-clock time reconnect пишется как справочная информация;
4. запись продолжается в тот же `signal.bin`.

Inter-BLoC связь реализуется через coordinator/`BlocListener`, а не через прямую
подписку `RecordingBloc` на stream другого BLoC. Это сохраняет явную композицию
scoped BLoC per device.

---

## Ошибки

Ошибки BLE мапятся в `BleFailure`:

```text
adapter_unavailable
permission_denied
device_not_found
connection_failed
connection_lost
notification_subscribe_failed
packet_decode_failed
```

UI показывает user-safe message. Техническая причина пишется в `app.log`.

---

## Проверки реализации

- discovery можно запустить/остановить без записи;
- remembered device можно подключить без scan;
- connection lost не удаляет buffered/saved samples;
- reconnect открывает новый segment;
- packets ignored when recording is inactive;
- packet decode failure не крашит приложение;
- two connected devices produce isolated recording scopes.
