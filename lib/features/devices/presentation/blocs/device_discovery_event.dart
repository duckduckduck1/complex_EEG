import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/ble_device.dart';

/// События [DeviceDiscoveryBloc] (см. docs/flutter_app/ble.md).
sealed class DeviceDiscoveryEvent extends Equatable {
  const DeviceDiscoveryEvent();

  @override
  List<Object?> get props => const [];
}

/// Пользователь запустил поиск; [namePrefix] фильтрует по имени модели.
final class DiscoveryStarted extends DeviceDiscoveryEvent {
  const DiscoveryStarted({this.namePrefix});

  final String? namePrefix;

  @override
  List<Object?> get props => [namePrefix];
}

/// Пользователь остановил поиск.
final class DiscoveryStopped extends DeviceDiscoveryEvent {
  const DiscoveryStopped();
}

/// Адаптер сообщил о найденном устройстве.
final class DeviceFound extends DeviceDiscoveryEvent {
  const DeviceFound(this.device);

  final DiscoveredDevice device;

  @override
  List<Object?> get props => [device];
}

/// Поиск завершился ошибкой.
final class DiscoveryFailed extends DeviceDiscoveryEvent {
  const DiscoveryFailed(this.failure);

  final BleFailure failure;

  @override
  List<Object?> get props => [failure];
}
