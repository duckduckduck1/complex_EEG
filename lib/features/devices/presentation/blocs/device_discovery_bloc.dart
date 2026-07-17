import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/ble_adapter.dart';
import '../../domain/ble_device.dart';
import 'device_discovery_event.dart';
import 'device_discovery_state.dart';

/// Поиск BLE-устройств.
///
/// Поиск можно запускать и останавливать без записи (docs/flutter_app/ble.md).
/// Поток найденных устройств приходит из [BleAdapter.scan]; BLoC накапливает их
/// без дубликатов по [BleDeviceId] и обновляет уже известные (например, RSSI).
///
/// Скан идёт непрерывно до фиксированного таймаута [_scanTimeout]: сам BLoC его
/// не перезапускает. Раньше здесь был watchdog, который перезапускал скан при
/// «тишине», но он считал уже отфильтрованный по целевому устройству поток —
/// и, не видя медленно рекламирующийся JDY-16, дёргал stop/startScan каждые
/// 5 с. Каждый перезапуск сбрасывал нагретый сканер Windows (и DeviceWatcher
/// из форка плагина) в холодное состояние, из-за чего устройство не находилось
/// вообще (лог стенда 2026-07-05). Непрерывный скан находит его штатно.
class DeviceDiscoveryBloc
    extends Bloc<DeviceDiscoveryEvent, DeviceDiscoveryState> {
  DeviceDiscoveryBloc({required BleAdapter adapter})
    : _adapter = adapter,
      super(const DeviceDiscoveryState()) {
    on<DiscoveryStarted>(_onStarted);
    on<DiscoveryStopped>(_onStopped);
    on<DeviceFound>(_onFound);
    on<DiscoveryFailed>(_onFailed);
  }

  final BleAdapter _adapter;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  Timer? _timeoutTimer;

  /// Момент старта текущего скана — только для диагностических логов
  /// «через сколько мс устройство появилось впервые» (debug-сборки).
  DateTime? _scanStartedAt;

  /// Фиксированный таймаут поиска: автостоп, чтобы не сканировать бесконечно.
  static const Duration _scanTimeout = Duration(seconds: 20);

  /// Старт (или повторный старт) поиска.
  ///
  /// Список устройств персистентный: найденные в прошлых поисках устройства
  /// остаются в списке, но их RSSI сбрасывается в null — метка «ещё не
  /// подтверждён текущим поиском». При повторном обнаружении [_onFound]
  /// обновляет запись целиком (включая RSSI). Ошибка прошлого поиска
  /// очищается.
  Future<void> _onStarted(
    DiscoveryStarted event,
    Emitter<DeviceDiscoveryState> emit,
  ) async {
    await _scanSub?.cancel();
    _timeoutTimer?.cancel();
    _scanStartedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint('[BLE discovery] scan started');
    }
    emit(
      DeviceDiscoveryState(
        status: DiscoveryStatus.scanning,
        devices: [
          for (final device in state.devices)
            DiscoveredDevice(id: device.id, name: device.name, rssi: null),
        ],
      ),
    );
    _scanSub = _adapter
        .scan(namePrefix: event.namePrefix)
        .listen(
          (device) => add(DeviceFound(device)),
          onError:
              (Object error) => add(
                DiscoveryFailed(
                  error is BleFailure
                      ? error
                      : BleFailure.adapterUnavailable(cause: error),
                ),
              ),
        );
    _timeoutTimer = Timer(_scanTimeout, () => add(const DiscoveryStopped()));
  }

  void _onFound(DeviceFound event, Emitter<DeviceDiscoveryState> emit) {
    if (state.status != DiscoveryStatus.scanning) {
      return;
    }
    final known = state.devices.any((d) => d.id == event.device.id);
    if (kDebugMode && !known) {
      final startedAt = _scanStartedAt;
      final sinceStartMs =
          startedAt == null
              ? null
              : DateTime.now().millisecondsSinceEpoch -
                  startedAt.millisecondsSinceEpoch;
      debugPrint(
        '[BLE discovery] first seen ${event.device.id.value} '
        'after $sinceStartMs ms',
      );
    }
    final devices =
        known
            ? [
              for (final device in state.devices)
                if (device.id == event.device.id) event.device else device,
            ]
            : [...state.devices, event.device];
    emit(state.copyWith(devices: devices));
  }

  Future<void> _onStopped(
    DiscoveryStopped event,
    Emitter<DeviceDiscoveryState> emit,
  ) async {
    if (kDebugMode) {
      debugPrint('[BLE discovery] scan stopped');
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await _adapter.stopScan();
    emit(state.copyWith(status: DiscoveryStatus.idle));
  }

  void _onFailed(DiscoveryFailed event, Emitter<DeviceDiscoveryState> emit) {
    if (kDebugMode) {
      debugPrint('[BLE discovery] scan failed: ${event.failure.message}');
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _scanSub?.cancel();
    _scanSub = null;
    emit(
      state.copyWith(status: DiscoveryStatus.failed, failure: event.failure),
    );
  }

  @override
  Future<void> close() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _scanSub?.cancel();
    return super.close();
  }
}
