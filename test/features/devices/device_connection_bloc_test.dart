import 'dart:async';

import 'package:eeg_app_max30003_stm32/core/errors/failures.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConnection implements BleConnection {
  final StreamController<List<int>> _packets =
      StreamController<List<int>>.broadcast();
  final Completer<void> _disconnected = Completer<void>();
  final List<List<int>> commands = <List<int>>[];
  bool disconnectCalled = false;

  @override
  Stream<List<int>> get packets => _packets.stream;

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> writeCommand(List<int> frame) async => commands.add(frame);

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  /// Сымитировать обрыв со стороны устройства.
  void dropFromDevice() {
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  void addPayload(List<int> payload) => _packets.add(payload);
}

class _FakeAdapter implements BleAdapter {
  _FakeAdapter({this.connection, this.failure});

  BleConnection? connection;
  BleFailure? failure;
  int connectCount = 0;
  BleDeviceId? lastConnectId;

  @override
  Future<BleConnection> connect(BleDeviceId id) async {
    connectCount++;
    lastConnectId = id;
    if (failure != null) throw failure!;
    return connection!;
  }

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

void main() {
  const deviceId = BleDeviceId('AA:BB:CC');

  late _FakeConnection connection;
  late _FakeAdapter adapter;
  late DeviceConnectionBloc bloc;
  late List<DeviceConnectionStatus> statuses;
  late StreamSubscription<DeviceConnectionState> sub;

  setUp(() {
    connection = _FakeConnection();
    adapter = _FakeAdapter(connection: connection);
    bloc = DeviceConnectionBloc(adapter: adapter);
    statuses = <DeviceConnectionStatus>[];
    sub = bloc.stream.listen((s) => statuses.add(s.status));
  });

  tearDown(() async {
    await sub.cancel();
    await bloc.close();
  });

  test('начальное состояние — disconnected', () {
    expect(bloc.state.status, DeviceConnectionStatus.disconnected);
    expect(bloc.activeConnection, isNull);
  });

  test('подключение проходит connecting → connected', () async {
    bloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();

    expect(statuses, [
      DeviceConnectionStatus.connecting,
      DeviceConnectionStatus.connected,
    ]);
    expect(bloc.state.deviceId, deviceId);
    expect(bloc.activeConnection, same(connection));
    expect(adapter.lastConnectId, deviceId);
  });

  test('ошибка подключения даёт failed с BleFailure', () async {
    adapter = _FakeAdapter(failure: BleFailure.connectionFailed());
    bloc = DeviceConnectionBloc(adapter: adapter);

    bloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();

    expect(bloc.state.status, DeviceConnectionStatus.failed);
    expect(bloc.state.failure?.code, 'ble.connection_failed');
    expect(bloc.activeConnection, isNull);
  });

  test('обрыв со стороны устройства переводит в lost', () async {
    bloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();

    connection.dropFromDevice();
    await pumpEventQueue();

    expect(bloc.state.status, DeviceConnectionStatus.lost);
    expect(bloc.activeConnection, isNull);
  });

  test('ручное переподключение после обрыва подключается заново', () async {
    bloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();
    connection.dropFromDevice();
    await pumpEventQueue();

    // Новое соединение для повторного подключения.
    adapter.connection = _FakeConnection();
    bloc.add(const ManualReconnectRequested());
    await pumpEventQueue();

    expect(bloc.state.status, DeviceConnectionStatus.connected);
    expect(adapter.connectCount, 2);
  });

  test('намеренное отключение даёт disconnected без lost', () async {
    bloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();

    bloc.add(const DisconnectRequested());
    await pumpEventQueue();
    await pumpEventQueue();

    expect(connection.disconnectCalled, isTrue);
    expect(bloc.state.status, DeviceConnectionStatus.disconnected);
    expect(statuses, isNot(contains(DeviceConnectionStatus.lost)));
  });

  test('переподключение игнорируется, если статус не lost/failed', () async {
    bloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();

    bloc.add(const ManualReconnectRequested());
    await pumpEventQueue();

    expect(adapter.connectCount, 1);
    expect(bloc.state.status, DeviceConnectionStatus.connected);
  });
}
