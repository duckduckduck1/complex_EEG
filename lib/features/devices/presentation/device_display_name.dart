import '../domain/ble_device.dart';

/// Человекочитаемое имя устройства для UI: `EEG-device:<XX>`, где `<XX>` —
/// последние 2 hex-символа MAC-адреса (последний октет). Несколько `JDY-16`
/// рядом неразличимы по рекламируемому имени (оно одинаковое у всех) —
/// различаем только по MAC. НЕ путать с [DiscoveredDevice.name]/
/// `DeviceSession.deviceName` (рекламируемое имя `JDY-16`, используется для
/// фильтра поиска, не для отображения).
String eegDisplayName(BleDeviceId id) {
  final mac = id.value;
  final suffix =
      mac.length >= 2 ? mac.substring(mac.length - 2).toUpperCase() : mac;
  return 'EEG-device:$suffix';
}
