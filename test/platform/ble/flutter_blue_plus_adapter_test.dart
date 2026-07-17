import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/platform/ble/flutter_blue_plus_adapter.dart';

/// Юнит-тесты ворот фильтра поиска [FlutterBluePlusAdapter.matchesTarget].
///
/// Закрепляют подтверждённый стендом факт (лог 2026-07-05): первый
/// advertisement-пакет JDY-16 приходит с сервисом 0xFFE0, но без имени —
/// такой пакет обязан проходить фильтр (иначе устройство появится в списке
/// только после scan response с именем, а то и не появится вовсе).
///
/// Ветка совпадения по имени здесь не проверяется: `device.advName` и
/// `device.platformName` читают статический кеш FlutterBluePlus, заполняемый
/// только платформенными событиями, — она проверяется на стенде.
ScanResult _scanResult({
  required String remoteId,
  List<Guid> serviceUuids = const [],
}) {
  return ScanResult(
    device: BluetoothDevice.fromId(remoteId),
    advertisementData: AdvertisementData(
      advName: '',
      txPowerLevel: null,
      appearance: null,
      connectable: true,
      manufacturerData: const {},
      serviceData: const {},
      serviceUuids: serviceUuids,
    ),
    rssi: -60,
    timeStamp: DateTime(2026, 7, 5),
  );
}

void main() {
  final adapter = FlutterBluePlusAdapter();
  final ffe0 = Guid('0000ffe0-0000-1000-8000-00805f9b34fb');
  final fee7 = Guid('0000fee7-0000-1000-8000-00805f9b34fb');

  test('пакет с сервисом 0xFFE0 без имени проходит фильтр', () {
    final result = _scanResult(
      remoteId: '3C:A5:51:9B:5C:75',
      serviceUuids: [ffe0, fee7],
    );
    expect(adapter.matchesTarget(result, 'JDY-16'), isTrue);
  });

  test('чужой пакет без имени и без 0xFFE0 отфильтровывается', () {
    final result = _scanResult(remoteId: '28:2B:B9:4B:C6:3F');
    expect(adapter.matchesTarget(result, 'JDY-16'), isFalse);
  });

  test('посторонний сервис (только 0xFEE7) не считается совпадением', () {
    final result = _scanResult(
      remoteId: '28:2B:B9:4B:C6:3F',
      serviceUuids: [fee7],
    );
    expect(adapter.matchesTarget(result, 'JDY-16'), isFalse);
  });

  test('пустой или null префикс пропускает любые устройства (raw scan)', () {
    final result = _scanResult(remoteId: '28:2B:B9:4B:C6:3F');
    expect(adapter.matchesTarget(result, null), isTrue);
    expect(adapter.matchesTarget(result, ''), isTrue);
  });
}
