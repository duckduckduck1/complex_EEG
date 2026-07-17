import 'package:equatable/equatable.dart';

import '../../domain/ble_device.dart';

/// События [DeviceConnectionBloc] (см. docs/flutter_app/ble.md).
sealed class DeviceConnectionEvent extends Equatable {
  const DeviceConnectionEvent();

  @override
  List<Object?> get props => const [];
}

/// Пользователь запросил подключение к устройству [deviceId].
final class ConnectRequested extends DeviceConnectionEvent {
  const ConnectRequested(this.deviceId);

  final BleDeviceId deviceId;

  @override
  List<Object?> get props => [deviceId];
}

/// Пользователь запросил отключение.
final class DisconnectRequested extends DeviceConnectionEvent {
  const DisconnectRequested();
}

/// Пользователь явно запросил переподключение после обрыва.
///
/// Автоматического переподключения нет — оператор контролирует обрыв
/// (docs/flutter_app/ble.md).
final class ManualReconnectRequested extends DeviceConnectionEvent {
  const ManualReconnectRequested();
}

/// Адаптер сообщил об обрыве соединения (внутреннее детектирование).
final class ConnectionLost extends DeviceConnectionEvent {
  const ConnectionLost();
}
