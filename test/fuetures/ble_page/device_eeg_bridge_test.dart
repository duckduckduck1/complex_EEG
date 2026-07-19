import 'dart:async';

import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:eeg_app_max30003_stm32/fuetures/ble_page/bloc/device_eeg_bridge.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConnection implements BleConnection {
  final StreamController<List<int>> _packets =
      StreamController<List<int>>.broadcast();
  final Completer<void> _disconnected = Completer<void>();

  @override
  Stream<List<int>> get packets => _packets.stream;

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> writeCommand(List<int> frame) async {}

  @override
  Future<void> disconnect() async {
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  void addPayload(List<int> payload) => _packets.add(payload);

  void dropFromDevice() {
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  Future<void> close() => _packets.close();
}

class _FakeAdapter implements BleAdapter {
  _FakeAdapter({this.connection});

  BleConnection? connection;

  @override
  Future<BleConnection> connect(BleDeviceId id) async => connection!;

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

/// Кодирует один отсчёт АЦП (18 бит) в 3 байта — тот же формат, что
/// [BleSampleDecoder] в `lib/features/devices/data/ble_sample_decoder.dart`.
List<int> _encodeSample(int adcValue) {
  final unsigned = adcValue < 0 ? adcValue + (1 << 18) : adcValue;
  final b0 = (unsigned >> 10) & 0xff;
  final b1 = (unsigned >> 2) & 0xff;
  final b2 = (unsigned << 6) & 0xff;
  return [b0, b1, b2];
}

void main() {
  const deviceId = BleDeviceId('AA:BB:CC');

  late _FakeConnection connection;
  late _FakeAdapter adapter;
  late DeviceConnectionBloc connectionBloc;
  late RtEegDataBloc rtEegDataBloc;
  late List<double> received;
  late StreamSubscription rtSub;

  setUp(() {
    connection = _FakeConnection();
    adapter = _FakeAdapter(connection: connection);
    connectionBloc = DeviceConnectionBloc(adapter: adapter);
    rtEegDataBloc = RtEegDataBloc(250);
    received = <double>[];
    rtSub = rtEegDataBloc.stream.listen((state) {
      // Точки лежат в bloc, а не в состоянии: состояние только сообщает, что
      // данные обновились.
      final spots = rtEegDataBloc.rawSpots;
      if (state is DataUpdated && spots.isNotEmpty) {
        received.add(spots.last.y);
      }
    });
  });

  tearDown(() async {
    await rtSub.cancel();
    await connectionBloc.close();
    await rtEegDataBloc.close();
    await connection.close();
  });

  test(
    'декодированные отсчёты доходят до RtEegDataBloc при connected',
    () async {
      final bridge = DeviceEegBridge(
        connection: connectionBloc,
        rtEegDataBloc: rtEegDataBloc,
      );

      connectionBloc.add(const ConnectRequested(deviceId));
      await pumpEventQueue();

      connection.addPayload([..._encodeSample(100), ..._encodeSample(-50)]);
      await pumpEventQueue();

      expect(received, hasLength(2));

      await bridge.dispose();
    },
  );

  test(
    'после обрыва соединения новые payload не доходят до RtEegDataBloc',
    () async {
      final bridge = DeviceEegBridge(
        connection: connectionBloc,
        rtEegDataBloc: rtEegDataBloc,
      );

      connectionBloc.add(const ConnectRequested(deviceId));
      await pumpEventQueue();

      connection.addPayload(_encodeSample(10));
      await pumpEventQueue();
      expect(received, hasLength(1));

      connection.dropFromDevice();
      await pumpEventQueue();

      // Соединение оборвано; отправка в тот же fake-поток больше не должна
      // доходить до RtEegDataBloc, так как мост отписался от packets.
      connection.addPayload(_encodeSample(20));
      await pumpEventQueue();

      expect(received, hasLength(1));

      await bridge.dispose();
    },
  );

  test('dispose отменяет подписку на состояние подключения', () async {
    final bridge = DeviceEegBridge(
      connection: connectionBloc,
      rtEegDataBloc: rtEegDataBloc,
    );

    await bridge.dispose();

    connectionBloc.add(const ConnectRequested(deviceId));
    await pumpEventQueue();

    connection.addPayload(_encodeSample(10));
    await pumpEventQueue();

    expect(received, isEmpty);
  });
}
