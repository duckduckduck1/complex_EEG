import 'package:equatable/equatable.dart';

/// Идентификатор BLE-устройства от адаптера (MAC/UUID).
///
/// Имя рекламируемого устройства — только фильтр поиска и доверенным
/// идентификатором не является; для запоминания и подключения используем этот
/// стабильный `device_id` (см. docs/reference/device_packet.md).
class BleDeviceId extends Equatable {
  const BleDeviceId(this.value);

  final String value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => value;
}

/// Найденное при сканировании устройство.
class DiscoveredDevice extends Equatable {
  const DiscoveredDevice({required this.id, required this.name, this.rssi});

  /// Стабильный идентификатор адаптера.
  final BleDeviceId id;

  /// Рекламируемое имя (например, `JDY-16`).
  final String name;

  /// Уровень сигнала, если адаптер его сообщил.
  final int? rssi;

  @override
  List<Object?> get props => [id, name, rssi];
}
