import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/ble_adapter.dart';
import '../../domain/ble_device.dart';
import 'device_connection_event.dart';
import 'device_connection_state.dart';

/// Управляет подключением к одному BLE-устройству.
///
/// Подключение создаётся на каждое устройство; автоматического переподключения
/// нет — после обрыва пользователь явно нажимает переподключение
/// (docs/flutter_app/ble.md). Активное [BleConnection] доступно через
/// [activeConnection] — его использует координатор устройства, направляя поток
/// отсчётов в запись; BLoC не раздаёт высокочастотный поток через состояние.
class DeviceConnectionBloc
    extends Bloc<DeviceConnectionEvent, DeviceConnectionState> {
  DeviceConnectionBloc({required BleAdapter adapter})
    : _adapter = adapter,
      super(const DeviceConnectionState.initial()) {
    on<ConnectRequested>(_onConnectRequested);
    on<ManualReconnectRequested>(_onManualReconnectRequested);
    on<DisconnectRequested>(_onDisconnectRequested);
    on<ConnectionLost>(_onConnectionLost);
  }

  final BleAdapter _adapter;
  BleConnection? _connection;

  /// Монотонный токен текущего подключения: гасит «висящие» колбэки
  /// `onDisconnected` от уже закрытых соединений.
  int _token = 0;

  /// Активное соединение (для координатора устройства); null, если нет.
  BleConnection? get activeConnection => _connection;

  Future<void> _onConnectRequested(
    ConnectRequested event,
    Emitter<DeviceConnectionState> emit,
  ) async {
    // Безопасность повторных событий: не стартуем поверх активного подключения.
    if (state.status == DeviceConnectionStatus.connecting ||
        state.status == DeviceConnectionStatus.connected ||
        state.status == DeviceConnectionStatus.reconnectingManually) {
      return;
    }
    await _establish(
      event.deviceId,
      emit,
      pending: DeviceConnectionStatus.connecting,
    );
  }

  Future<void> _onManualReconnectRequested(
    ManualReconnectRequested event,
    Emitter<DeviceConnectionState> emit,
  ) async {
    final deviceId = state.deviceId;
    if (deviceId == null ||
        (state.status != DeviceConnectionStatus.lost &&
            state.status != DeviceConnectionStatus.failed)) {
      return;
    }
    await _establish(
      deviceId,
      emit,
      pending: DeviceConnectionStatus.reconnectingManually,
    );
  }

  Future<void> _establish(
    BleDeviceId deviceId,
    Emitter<DeviceConnectionState> emit, {
    required DeviceConnectionStatus pending,
  }) async {
    emit(DeviceConnectionState(status: pending, deviceId: deviceId));
    try {
      final connection = await _adapter.connect(deviceId);
      _connection = connection;
      final token = ++_token;
      // Обрыв со стороны устройства приходит как завершение onDisconnected.
      // Ждать его здесь нельзя — это подписка на будущее событие, а не шаг
      // подключения; `unawaited` говорит это и анализатору, и читателю.
      unawaited(
        connection.onDisconnected.then((_) {
          if (!isClosed && token == _token) {
            add(const ConnectionLost());
          }
        }),
      );
      emit(
        DeviceConnectionState(
          status: DeviceConnectionStatus.connected,
          deviceId: deviceId,
        ),
      );
    } on BleFailure catch (failure) {
      _connection = null;
      emit(
        DeviceConnectionState(
          status: DeviceConnectionStatus.failed,
          deviceId: deviceId,
          failure: failure,
        ),
      );
    } catch (error) {
      _connection = null;
      emit(
        DeviceConnectionState(
          status: DeviceConnectionStatus.failed,
          deviceId: deviceId,
          failure: BleFailure.connectionFailed(cause: error),
        ),
      );
    }
  }

  Future<void> _onDisconnectRequested(
    DisconnectRequested event,
    Emitter<DeviceConnectionState> emit,
  ) async {
    // Гасим колбэк onDisconnected, чтобы намеренное отключение не дало `lost`.
    _token++;
    final connection = _connection;
    _connection = null;
    await connection?.disconnect();
    emit(
      DeviceConnectionState(
        status: DeviceConnectionStatus.disconnected,
        deviceId: state.deviceId,
      ),
    );
  }

  void _onConnectionLost(
    ConnectionLost event,
    Emitter<DeviceConnectionState> emit,
  ) {
    _connection = null;
    emit(
      DeviceConnectionState(
        status: DeviceConnectionStatus.lost,
        deviceId: state.deviceId,
      ),
    );
  }

  @override
  Future<void> close() async {
    _token++;
    await _connection?.disconnect();
    _connection = null;
    return super.close();
  }
}
