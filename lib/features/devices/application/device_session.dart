import '../domain/ble_device.dart';
import '../presentation/blocs/device_connection_bloc.dart';

/// Активная сессия одного BLE-устройства.
///
/// Каждое подключённое устройство ведёт независимую сессию подключения
/// (docs/flutter_app/architecture.md, «Изоляция нескольких устройств») —
/// ошибка или обрыв одного устройства не влияет на другие. Владелец —
/// [SessionsCubit][../application/sessions_cubit.dart]; UI показывает сессию
/// отдельной вкладкой/панелью.
///
/// Сессия отвечает только за подключение. Визуализация сигнала
/// (`RtEegDataBloc`/график) сюда не входит: «подключиться к устройству» и
/// «показать график» — разные действия и будут связаны отдельным шагом
/// (см. план архитектуры Flutter-приложения).
class DeviceSession {
  DeviceSession({
    required this.deviceId,
    required this.deviceName,
    required this.connection,
  });

  /// Стабильный идентификатор устройства (см. [BleDeviceId]).
  final BleDeviceId deviceId;

  /// Исходное рекламируемое имя устройства (advName), НЕ display-имя для UI.
  final String deviceName;

  /// BLoC подключения этой сессии.
  final DeviceConnectionBloc connection;

  /// Освободить ресурсы сессии.
  Future<void> dispose() => connection.close();
}
