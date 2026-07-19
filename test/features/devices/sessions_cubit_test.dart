import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/sessions_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';

class _FakeConnection implements BleConnection {
  final StreamController<List<int>> _packets =
      StreamController<List<int>>.broadcast();
  final Completer<void> _disconnected = Completer<void>();
  bool disconnectCalled = false;

  @override
  Stream<List<int>> get packets => _packets.stream;

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> writeCommand(List<int> frame) async {}

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    if (!_disconnected.isCompleted) _disconnected.complete();
    // Настоящее устройство после отключения пакетов не шлёт — фейк тоже.
    await _packets.close();
  }
}

class _FakeAdapter implements BleAdapter {
  final List<BleDeviceId> connectedIds = <BleDeviceId>[];
  final Map<String, _FakeConnection> connections = {};

  @override
  Future<BleConnection> connect(BleDeviceId id) async {
    connectedIds.add(id);
    final connection = _FakeConnection();
    connections[id.value] = connection;
    return connection;
  }

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

void main() {
  const deviceA = DiscoveredDevice(
    id: BleDeviceId('AA:BB:CC'),
    name: 'JDY-16-A',
  );
  const deviceB = DiscoveredDevice(
    id: BleDeviceId('DD:EE:FF'),
    name: 'JDY-16-B',
  );

  late _FakeAdapter adapter;
  late SessionsCubit cubit;

  setUp(() {
    adapter = _FakeAdapter();
    cubit = SessionsCubit(adapter: adapter);
  });

  tearDown(() async {
    await cubit.close();
  });

  test('начальное состояние — пустой список сессий', () {
    expect(cubit.state, isEmpty);
  });

  test('openSession создаёт сессию и запрашивает подключение', () async {
    cubit.openSession(deviceA);
    await pumpEventQueue();

    expect(cubit.state, hasLength(1));
    expect(cubit.hasSession(deviceA.id), isTrue);
    expect(cubit.sessionFor(deviceA.id)?.deviceName, 'JDY-16-A');
    expect(adapter.connectedIds, [deviceA.id]);
  });

  test(
    'повторный openSession для того же id не создаёт вторую сессию',
    () async {
      cubit.openSession(deviceA);
      await pumpEventQueue();
      cubit.openSession(deviceA);
      await pumpEventQueue();

      expect(cubit.state, hasLength(1));
      expect(adapter.connectedIds, [deviceA.id]);
    },
  );

  test('closeSession диспозит и убирает сессию из списка', () async {
    cubit.openSession(deviceA);
    await pumpEventQueue();

    final connection = adapter.connections[deviceA.id.value]!;
    await cubit.closeSession(deviceA.id);

    expect(connection.disconnectCalled, isTrue);
    expect(cubit.hasSession(deviceA.id), isFalse);
    expect(cubit.state, isEmpty);
  });

  test('closeSession для несуществующего id — no-op', () async {
    await cubit.closeSession(deviceA.id);
    expect(cubit.state, isEmpty);
  });

  test('несколько сессий для разных устройств сосуществуют', () async {
    cubit.openSession(deviceA);
    await pumpEventQueue();
    cubit.openSession(deviceB);
    await pumpEventQueue();

    expect(cubit.state, hasLength(2));
    expect(cubit.hasSession(deviceA.id), isTrue);
    expect(cubit.hasSession(deviceB.id), isTrue);

    await cubit.closeSession(deviceA.id);

    expect(cubit.hasSession(deviceA.id), isFalse);
    expect(cubit.hasSession(deviceB.id), isTrue);
    expect(cubit.state, hasLength(1));
  });

  test('close() диспозит все активные сессии', () async {
    cubit.openSession(deviceA);
    await pumpEventQueue();
    cubit.openSession(deviceB);
    await pumpEventQueue();

    await cubit.close();

    expect(adapter.connections[deviceA.id.value]!.disconnectCalled, isTrue);
    expect(adapter.connections[deviceB.id.value]!.disconnectCalled, isTrue);
  });
}
