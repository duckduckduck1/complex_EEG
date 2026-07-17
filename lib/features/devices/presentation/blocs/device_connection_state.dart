import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/ble_device.dart';

/// Фаза подключения к устройству (см. docs/flutter_app/ble.md).
enum DeviceConnectionStatus {
  /// Не подключено.
  disconnected,

  /// Идёт подключение.
  connecting,

  /// Подключено, поток сигнала доступен.
  connected,

  /// Связь потеряна; ждём ручного переподключения.
  lost,

  /// Идёт ручное переподключение.
  reconnectingManually,

  /// Подключение не удалось.
  failed,
}

/// Неизменяемое состояние [DeviceConnectionBloc].
class DeviceConnectionState extends Equatable {
  const DeviceConnectionState({
    required this.status,
    this.deviceId,
    this.failure,
  });

  /// Начальное состояние — без устройства.
  const DeviceConnectionState.initial()
    : status = DeviceConnectionStatus.disconnected,
      deviceId = null,
      failure = null;

  /// Текущая фаза подключения.
  final DeviceConnectionStatus status;

  /// Устройство, к которому идёт/шло подключение.
  final BleDeviceId? deviceId;

  /// Последняя ошибка BLE, безопасная для показа пользователю.
  final BleFailure? failure;

  /// Доступен ли сейчас поток сигнала.
  bool get isConnected => status == DeviceConnectionStatus.connected;

  @override
  List<Object?> get props => [status, deviceId, failure];
}
