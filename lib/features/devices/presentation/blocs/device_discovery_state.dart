import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/ble_device.dart';

/// Фаза поиска устройств.
enum DiscoveryStatus { idle, scanning, failed }

/// Неизменяемое состояние [DeviceDiscoveryBloc].
class DeviceDiscoveryState extends Equatable {
  const DeviceDiscoveryState({
    this.status = DiscoveryStatus.idle,
    this.devices = const [],
    this.failure,
  });

  /// Текущая фаза поиска.
  final DiscoveryStatus status;

  /// Найденные устройства (без дубликатов по id).
  final List<DiscoveredDevice> devices;

  /// Ошибка поиска, безопасная для показа пользователю.
  final BleFailure? failure;

  static const Object _unset = Object();

  DeviceDiscoveryState copyWith({
    DiscoveryStatus? status,
    List<DiscoveredDevice>? devices,
    Object? failure = _unset,
  }) {
    return DeviceDiscoveryState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      failure: failure == _unset ? this.failure : failure as BleFailure?,
    );
  }

  @override
  List<Object?> get props => [status, devices, failure];
}
