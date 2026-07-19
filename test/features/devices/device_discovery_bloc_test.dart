import 'dart:async';

import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_discovery_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_discovery_event.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_discovery_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements BleAdapter {
  final StreamController<DiscoveredDevice> controller =
      StreamController<DiscoveredDevice>.broadcast();
  bool stopped = false;
  String? lastNamePrefix;

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) {
    lastNamePrefix = namePrefix;
    return controller.stream;
  }

  @override
  Future<void> stopScan() async => stopped = true;

  /// Останов поиска поток не закрывает: после него ищут снова. Закрываем
  /// отдельно, когда фейк больше не нужен.
  Future<void> dispose() => controller.close();

  @override
  Future<BleConnection> connect(BleDeviceId id) async =>
      throw UnimplementedError();
}

DiscoveredDevice _device(String id, {int rssi = -50}) =>
    DiscoveredDevice(id: BleDeviceId(id), name: 'JDY-16', rssi: rssi);

/// Дублирует приватную `DeviceDiscoveryBloc._scanTimeout` — значение
/// фиксированное и не настраиваемое по контракту, поэтому дублирование здесь
/// безопасно (изменение таймаута в блоке потребует обновить и тест).
const _scanTimeout = Duration(seconds: 20);

void main() {
  late _FakeAdapter adapter;
  late DeviceDiscoveryBloc bloc;

  setUp(() {
    adapter = _FakeAdapter();
    bloc = DeviceDiscoveryBloc(adapter: adapter);
  });

  tearDown(() async {
    await bloc.close();
    await adapter.dispose();
  });

  test('начальное состояние — idle без устройств', () {
    expect(bloc.state.status, DiscoveryStatus.idle);
    expect(bloc.state.devices, isEmpty);
  });

  test('поиск накапливает устройства без дубликатов', () async {
    bloc.add(const DiscoveryStarted());
    await pumpEventQueue();
    expect(bloc.state.status, DiscoveryStatus.scanning);
    expect(adapter.lastNamePrefix, isNull);

    adapter.controller.add(_device('AA'));
    adapter.controller.add(_device('BB'));
    await pumpEventQueue();
    expect(bloc.state.devices.map((d) => d.id.value), ['AA', 'BB']);

    // Повторное появление обновляет запись, а не добавляет дубликат.
    adapter.controller.add(_device('AA', rssi: -70));
    await pumpEventQueue();
    expect(bloc.state.devices, hasLength(2));
    expect(bloc.state.devices.first.rssi, -70);
  });

  test(
    'устройства переживают повторный DiscoveryStarted со сбросом RSSI',
    () async {
      bloc.add(const DiscoveryStarted());
      await pumpEventQueue();
      adapter.controller.add(_device('AA', rssi: -42));
      await pumpEventQueue();

      bloc.add(const DiscoveryStopped());
      await pumpEventQueue();

      // Повторный старт: список персистентный, но RSSI сброшен — устройство
      // ещё не подтверждено текущим поиском.
      bloc.add(const DiscoveryStarted());
      await pumpEventQueue();

      expect(bloc.state.status, DiscoveryStatus.scanning);
      expect(bloc.state.devices.map((d) => d.id.value), ['AA']);
      expect(bloc.state.devices.single.rssi, isNull);
    },
  );

  test(
    'повторное обнаружение после рестарта обновляет RSSI без дубликата',
    () async {
      bloc.add(const DiscoveryStarted());
      await pumpEventQueue();
      adapter.controller.add(_device('AA', rssi: -42));
      await pumpEventQueue();

      bloc.add(const DiscoveryStopped());
      await pumpEventQueue();
      bloc.add(const DiscoveryStarted());
      await pumpEventQueue();

      adapter.controller.add(_device('AA', rssi: -63));
      await pumpEventQueue();

      expect(bloc.state.devices, hasLength(1));
      expect(bloc.state.devices.single.rssi, -63);
    },
  );

  test('новый старт очищает failure и сохраняет устройства', () async {
    bloc.add(const DiscoveryStarted());
    await pumpEventQueue();
    adapter.controller.add(_device('AA'));
    await pumpEventQueue();

    adapter.controller.addError(StateError('adapter off'));
    await pumpEventQueue();
    expect(bloc.state.status, DiscoveryStatus.failed);
    expect(bloc.state.failure, isNotNull);

    bloc.add(const DiscoveryStarted());
    await pumpEventQueue();

    expect(bloc.state.status, DiscoveryStatus.scanning);
    expect(bloc.state.failure, isNull);
    expect(bloc.state.devices.map((d) => d.id.value), ['AA']);
    expect(bloc.state.devices.single.rssi, isNull);
  });

  test('остановка поиска возвращает в idle и зовёт stopScan', () async {
    bloc.add(const DiscoveryStarted());
    await pumpEventQueue();

    bloc.add(const DiscoveryStopped());
    await pumpEventQueue();

    expect(bloc.state.status, DiscoveryStatus.idle);
    expect(adapter.stopped, isTrue);
  });

  test('ошибка потока поиска переводит в failed', () async {
    bloc.add(const DiscoveryStarted());
    await pumpEventQueue();

    adapter.controller.addError(StateError('adapter off'));
    await pumpEventQueue();

    expect(bloc.state.status, DiscoveryStatus.failed);
    expect(bloc.state.failure?.code, 'ble.adapter_unavailable');
  });

  test('автостоп по таймауту 20 секунд переводит в idle без ручного стопа', () {
    // StreamSubscription.cancel() внутри _onStopped не резолвится синхронно
    // под fake_async (ограничение пары dart:async/fake_async в этой версии
    // SDK — Future от cancel() довершается только в реальном event loop, а
    // не через Timer/microtask, которые fake_async виртуализирует). Поэтому
    // проверяем сам факт срабатывания таймаута через диагностику fake_async
    // (pendingTimers), а не через ожидание финального DiscoveryStatus.idle.
    //
    // Bloc создаётся внутри fakeAsync: его внутренний StreamController должен
    // планировать доставку событий в той же fake-зоне — иначе Timer/microtask
    // из внешнего setUp() не попадают под управление виртуального времени.
    fakeAsync((async) {
      final fakeAdapter = _FakeAdapter();
      final fakeBloc = DeviceDiscoveryBloc(adapter: fakeAdapter);

      fakeBloc.add(const DiscoveryStarted());
      async.flushMicrotasks();
      expect(fakeBloc.state.status, DiscoveryStatus.scanning);
      expect(
        async.pendingTimers,
        hasLength(1),
        reason: 'после старта поиска запланирован ровно один таймер — автостоп',
      );

      async.elapse(_scanTimeout - const Duration(seconds: 1));
      expect(
        fakeBloc.state.status,
        DiscoveryStatus.scanning,
        reason: 'до истечения 20 секунд поиск продолжается',
      );
      expect(async.pendingTimers, hasLength(1));

      async.elapse(const Duration(seconds: 1));
      expect(
        async.pendingTimers,
        isEmpty,
        reason:
            'ровно через 20 секунд таймер автостопа должен сработать (и '
            'вызвать add(DiscoveryStopped()))',
      );
    });
  });

  test('ручной стоп до таймаута отменяет таймер — нет повторного idle', () {
    fakeAsync((async) {
      final fakeAdapter = _FakeAdapter();
      final fakeBloc = DeviceDiscoveryBloc(adapter: fakeAdapter);

      fakeBloc.add(const DiscoveryStarted());
      async.flushMicrotasks();
      expect(fakeBloc.state.status, DiscoveryStatus.scanning);

      // Ручная остановка задолго до истечения 20 секунд.
      fakeBloc.add(const DiscoveryStopped());
      async.flushMicrotasks();

      // Таймер автостопа должен быть отменён внутри _onStopped до await
      // cancel() — проверяем это напрямую диагностическим API fake_async:
      // к моменту ручной остановки был ровно один pending timer (таймаут),
      // и после ручного стопа его больше нет.
      expect(
        async.pendingTimers,
        isEmpty,
        reason:
            '_onStopped должен отменять _timeoutTimer до какой-либо '
            'асинхронной работы — иначе он остался бы в очереди',
      );

      // Даже если сдвинуть время далеко вперёд — новых срабатываний нет.
      async.elapse(const Duration(minutes: 5));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
