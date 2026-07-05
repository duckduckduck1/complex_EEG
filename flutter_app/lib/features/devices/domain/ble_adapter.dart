import 'ble_device.dart';

/// Активное соединение с одним BLE-устройством.
///
/// Абстрагирует характеристику сигнала: приложение подписывается на [packets]
/// (сырые payload'ы notify) и пишет в ту же характеристику команды через
/// [writeCommand] (например, ФБМ). Декодирование payload в микровольты — задача
/// слоя записи (см. docs/reference/device_packet.md и docs/flutter_app/ble.md).
abstract interface class BleConnection {
  /// Поток payload'ов notify характеристики сигнала (сырые байты, кратные 3).
  Stream<List<int>> get packets;

  /// Завершается, когда соединение разорвано (устройством, потерей связи или
  /// после [disconnect]). Автоматическое переподключение не выполняется.
  Future<void> get onDisconnected;

  /// Записать кадр команды в характеристику сигнала (например, кадр ФБМ).
  Future<void> writeCommand(List<int> frame);

  /// Разорвать соединение и освободить ресурсы.
  Future<void> disconnect();
}

/// Доступ к BLE-адаптеру: поиск устройств и подключение.
///
/// Порт скрывает конкретный плагин (на первом стенде — `flutter_blue_plus`);
/// BLoC'и и координаторы работают только с этим интерфейсом, что делает их
/// тестируемыми без железа (docs/flutter_app/testing.md).
abstract interface class BleAdapter {
  /// Сканировать устройства. [namePrefix] фильтрует по рекламируемому имени
  /// (например, `JDY-16`).
  Stream<DiscoveredDevice> scan({String? namePrefix});

  /// Остановить сканирование.
  Future<void> stopScan();

  /// Подключиться к устройству [id] и подписаться на характеристику сигнала.
  ///
  /// Бросает [BleFailure] при неудаче (adapter_unavailable, connection_failed,
  /// notification_subscribe_failed и т.п.).
  Future<BleConnection> connect(BleDeviceId id);
}
