import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/ble_adapter.dart';
import '../domain/ble_device.dart';
import '../presentation/blocs/device_connection_bloc.dart';
import '../presentation/blocs/device_connection_event.dart';
import 'device_session.dart';

/// Менеджер активных сессий устройств.
///
/// Держит список [DeviceSession] — по одной на подключаемое устройство.
/// Каждое устройство ведёт независимую сессию подключения
/// (docs/flutter_app/architecture.md, «Изоляция нескольких устройств»):
/// ошибка или обрыв одной сессии не меняет состояние других.
///
/// Эта кубита отвечает только за жизненный цикл подключения. Визуализация
/// сигнала (`RtEegDataBloc`/график) в сессии не хранится — «подключиться» и
/// «показать график» разные действия и будут связаны на одном из следующих
/// шагов.
class SessionsCubit extends Cubit<List<DeviceSession>> {
  SessionsCubit({required BleAdapter adapter})
    : _adapter = adapter,
      super(const []);

  final BleAdapter _adapter;

  /// Есть ли уже сессия для устройства [id].
  bool hasSession(BleDeviceId id) => state.any((s) => s.deviceId == id);

  /// Найти активную сессию устройства [id], если она есть.
  DeviceSession? sessionFor(BleDeviceId id) {
    for (final session in state) {
      if (session.deviceId == id) {
        return session;
      }
    }
    return null;
  }

  /// Открыть сессию для [device] и начать подключение.
  ///
  /// Если сессия для этого устройства уже существует — no-op (безопасность
  /// повторных вызовов, не пересоздаёт подключение).
  void openSession(DiscoveredDevice device) {
    if (hasSession(device.id)) {
      return;
    }
    final connection = DeviceConnectionBloc(adapter: _adapter);
    connection.add(ConnectRequested(device.id));
    emit([
      ...state,
      DeviceSession(
        deviceId: device.id,
        deviceName: device.name,
        connection: connection,
      ),
    ]);
  }

  /// Закрыть сессию устройства [id] и освободить её ресурсы.
  ///
  /// Если сессии нет — no-op.
  Future<void> closeSession(BleDeviceId id) async {
    final target = sessionFor(id);
    if (target == null) {
      return;
    }
    await target.dispose();
    emit(state.where((s) => s.deviceId != id).toList());
  }

  @override
  Future<void> close() async {
    for (final session in state) {
      await session.dispose();
    }
    return super.close();
  }
}
