import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/errors/failures.dart';
import '../../features/devices/domain/ble_adapter.dart';
import '../../features/devices/domain/ble_device.dart';

/// Реальный BLE-адаптер поверх `flutter_blue_plus` (на Windows — через WinRT).
///
/// Реализует порт [BleAdapter] по контракту устройства
/// (docs/reference/device_packet.md): поиск по имени модели, подключение,
/// подписка на характеристику сигнала `ffe1` и запись команд (ФБМ) в неё же.
///
/// ВНИМАНИЕ: код требует реального BLE-стека и проверяется на стенде, а не
/// юнит-тестами; здесь гарантируется только корректная компиляция против API.
class FlutterBluePlusAdapter implements BleAdapter {
  FlutterBluePlusAdapter({
    Duration connectTimeout = const Duration(seconds: 15),
  }) : _connectTimeout = connectTimeout;

  final Duration _connectTimeout;

  /// UUID характеристики сигнала/управления (см. device_packet.md).
  static final Guid signalCharacteristic = Guid(
    '0000ffe1-0000-1000-8000-00805f9b34fb',
  );

  /// UUID сервиса, в котором у модулей семейства HM-10/JDY лежит
  /// характеристика сигнала [signalCharacteristic] (0xFFE1 внутри 0xFFE0).
  ///
  /// Подтверждено стендом (лог 2026-07-05): первый advertisement-пакет
  /// JDY-16 приходит с сервисом 0xFFE0, но без имени — имя догоняет позже,
  /// в scan response при активном сканировании. Поэтому ffe0-ветка
  /// [_matchesTarget] даёт самое раннее появление устройства в поиске.
  /// Контракт поиска описан в docs/reference/device_packet.md.
  static final Guid _signalServiceGuid = Guid(
    '0000ffe0-0000-1000-8000-00805f9b34fb',
  );

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) async* {
    // Нативные фильтры withNames/withServices намеренно не передаются:
    // на WinRT они игнорируются нативно, а на Android дали бы AND-семантику
    // с нативным фильтром и сломали бы дизъюнкцию «имя ИЛИ сервис» из
    // [matchesTarget]. Вся фильтрация — в Dart, ниже по цепочке.
    //
    // Скорость обнаружения на Windows обеспечивает параллельный DeviceWatcher
    // в форке нативного плагина (third_party/flutter_blue_plus_winrt): без
    // него первое обнаружение занимало секунды/минуты из-за ленивого duty
    // cycle. Прежний Dart-костыль (периодический FlutterBluePlus.systemDevices)
    // не помогал (лог стенда: возвращал пустой кеш) и удалён.
    await FlutterBluePlus.startScan(oneByOne: true);
    // Диагностика медленного поиска: отличаем «события не приходят вообще»
    // (мёртвый watcher) от «приходят, но редко» (низкий duty cycle / редкая
    // реклама). Подсчёт намеренно идёт по всему эфиру — ДО фильтра
    // [matchesTarget], чтобы `[BLE scan]`-логи показывали весь поток
    // событий сканера. Только debug-сборки; формат DiscoveredDevice не
    // меняется.
    final diagnostics = kDebugMode ? _ScanDiagnostics() : null;
    yield* FlutterBluePlus.onScanResults
        .expand((results) => results)
        .map((result) {
          diagnostics?.onResult(result);
          return result;
        })
        .where((result) => matchesTarget(result, namePrefix))
        .map(
          (result) => DiscoveredDevice(
            id: BleDeviceId(result.device.remoteId.str),
            name:
                result.device.advName.isNotEmpty
                    ? result.device.advName
                    : result.device.platformName,
            rssi: result.rssi,
          ),
        );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<BleConnection> connect(BleDeviceId id) async {
    final device = BluetoothDevice.fromId(id.value);
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: _connectTimeout,
      );
    } catch (error) {
      throw BleFailure.connectionFailed(cause: error);
    }

    try {
      final services = await device.discoverServices();
      final characteristic = _findSignalCharacteristic(services);
      await characteristic.setNotifyValue(true);
      return FlutterBluePlusConnection(
        device: device,
        characteristic: characteristic,
      );
    } catch (error) {
      await device.disconnect();
      throw BleFailure.notificationSubscribeFailed(cause: error);
    }
  }

  /// Совпадает ли результат сканирования с искомым устройством.
  ///
  /// Проверка по имени — официально задокументированная в device_packet.md.
  /// Дополнительно (через ИЛИ) устройство считается совпавшим, если в его
  /// рекламных данных заявлен сервис [_signalServiceGuid]. Это подтверждённый
  /// стендом факт (лог 2026-07-05): первый advertisement-пакет JDY-16
  /// содержит 0xFFE0 без имени, имя приходит позже в scan response при
  /// активном сканировании — ffe0-ветка даёт самое раннее появление
  /// устройства. Дизъюнкция «имя ИЛИ сервис» работает только потому, что
  /// [scan] намеренно не передаёт `withNames`/`withServices` в `startScan()`
  /// (см. комментарий там) — иначе на платформах с нативной AND-фильтрацией
  /// семантика бы изменилась.
  ///
  /// Видим для тестов: это ворота всего списка устройств (регрессия — пустой
  /// список на стенде), сервисная ветка проверяется юнитами. Ветка имени
  /// юнитами непроверяема: `device.advName`/`platformName` читают статический
  /// кеш FlutterBluePlus, который заполняется только платформенными
  /// событиями — она проверяется на стенде.
  @visibleForTesting
  bool matchesTarget(ScanResult result, String? namePrefix) {
    if (namePrefix == null || namePrefix.isEmpty) {
      return true;
    }
    final matchesName =
        result.device.advName.contains(namePrefix) ||
        result.device.platformName.contains(namePrefix);
    final matchesService = result.advertisementData.serviceUuids.contains(
      _signalServiceGuid,
    );
    return matchesName || matchesService;
  }

  BluetoothCharacteristic _findSignalCharacteristic(
    List<BluetoothService> services,
  ) {
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == signalCharacteristic) {
          return characteristic;
        }
      }
    }
    throw const FormatException('Характеристика сигнала ffe1 не найдена');
  }
}

/// Соединение с устройством поверх `flutter_blue_plus`.
class FlutterBluePlusConnection implements BleConnection {
  FlutterBluePlusConnection({
    required BluetoothDevice device,
    required BluetoothCharacteristic characteristic,
  }) : _device = device,
       _characteristic = characteristic,
       _onDisconnected = device.connectionState
           .firstWhere(
             (state) => state == BluetoothConnectionState.disconnected,
           )
           .then((_) {});

  final BluetoothDevice _device;
  final BluetoothCharacteristic _characteristic;
  final Future<void> _onDisconnected;

  @override
  Stream<List<int>> get packets => _characteristic.onValueReceived;

  @override
  Future<void> get onDisconnected => _onDisconnected;

  @override
  Future<void> writeCommand(List<int> frame) => _characteristic.write(
    frame,
    withoutResponse: _characteristic.properties.writeWithoutResponse,
  );

  @override
  Future<void> disconnect() => _device.disconnect();
}

/// Диагностика потока сканирования для отладки медленного BLE-поиска.
///
/// Логирует время от старта скана до первого события и периодическую сводку
/// (сколько событий, сколько уникальных устройств, сколько прошло секунд).
/// Создаётся в [FlutterBluePlusAdapter.scan] только под [kDebugMode]; таймеров
/// не заводит — только [Stopwatch] и счётчики.
class _ScanDiagnostics {
  _ScanDiagnostics() {
    _sinceScanStart.start();
  }

  /// Каждое сколько событий печатать сводку по потоку сканирования.
  static const int _summaryEvery = 25;

  final Stopwatch _sinceScanStart = Stopwatch();
  final Set<String> _seenIds = <String>{};
  int _eventCount = 0;

  void onResult(ScanResult result) {
    _eventCount += 1;
    _seenIds.add(result.device.remoteId.str);
    if (_eventCount == 1) {
      debugPrint(
        '[BLE scan] first event after ${_sinceScanStart.elapsedMilliseconds} ms',
      );
    }
    if (_eventCount % _summaryEvery == 0) {
      debugPrint(
        '[BLE scan] events: $_eventCount, '
        'unique devices: ${_seenIds.length}, '
        'elapsed: ${_sinceScanStart.elapsed.inSeconds} s',
      );
    }
  }
}
