import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/application/recording_bridge.dart';
import 'package:iot/features/recording/domain/recording_models.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

void main() {
  const deviceId = BleDeviceId('AA:BB:CC');

  test(
    'bridge pauses recording on lost and resumes after manual reconnect',
    () async {
      final adapter = _FakeAdapter(connection: _FakeConnection());
      final connectionBloc = DeviceConnectionBloc(adapter: adapter);
      final recordingBloc = RecordingBloc(
        storage: _MemoryExperimentStorage(),
        filterFactory: const PassThroughStreamingFilterFactory(),
        idGenerator: const _FixedIdGenerator(),
      );
      final bridge = RecordingBridge(
        connection: connectionBloc,
        recordingBloc: recordingBloc,
      );
      addTearDown(() async {
        await bridge.dispose();
        await recordingBloc.close();
        await connectionBloc.close();
      });

      recordingBloc.add(
        const RecordingStartRequested(
          RecordingStartConfig(rootDirectory: 'memory-root'),
        ),
      );
      await pumpEventQueue();
      connectionBloc.add(const ConnectRequested(deviceId));
      await pumpEventQueue();

      adapter.connection!.dropFromDevice();
      await pumpEventQueue(times: 4);

      expect(recordingBloc.state.status, RecordingStatus.pausedByDisconnect);
      expect(recordingBloc.state.segments.single.endSample, 0);
      expect(recordingBloc.state.gaps.single.sampleIndex, 0);

      adapter.connection = _FakeConnection();
      connectionBloc.add(const ManualReconnectRequested());
      await pumpEventQueue(times: 4);

      expect(recordingBloc.state.status, RecordingStatus.recording);
      expect(recordingBloc.state.segments, hasLength(2));
      expect(recordingBloc.state.activeSegmentId, 'seg_2');
      expect(recordingBloc.state.gaps.single.endedAtWallClock, isNotNull);
    },
  );

  test(
    'bridge queues resumed when reconnect completes before lost flush finishes',
    () async {
      final storage = _DelayedFlushExperimentStorage();
      final adapter = _FakeAdapter(connection: _FakeConnection());
      final connectionBloc = DeviceConnectionBloc(adapter: adapter);
      final recordingBloc = RecordingBloc(
        storage: storage,
        filterFactory: const PassThroughStreamingFilterFactory(),
        idGenerator: const _FixedIdGenerator(),
      );
      final bridge = RecordingBridge(
        connection: connectionBloc,
        recordingBloc: recordingBloc,
      );
      addTearDown(() async {
        await bridge.dispose();
        await recordingBloc.close();
        await connectionBloc.close();
      });

      recordingBloc.add(
        const RecordingStartRequested(
          RecordingStartConfig(rootDirectory: 'memory-root'),
        ),
      );
      await pumpEventQueue();
      connectionBloc.add(const ConnectRequested(deviceId));
      await pumpEventQueue();

      storage.delayNextFlush();
      adapter.connection!.dropFromDevice();
      await pumpEventQueue(times: 3);

      expect(connectionBloc.state.status, DeviceConnectionStatus.lost);
      expect(recordingBloc.state.status, RecordingStatus.recording);

      adapter.connection = _FakeConnection();
      connectionBloc.add(const ManualReconnectRequested());
      await pumpEventQueue(times: 2);

      expect(recordingBloc.state.status, RecordingStatus.recording);

      storage.completeDelayedFlush();
      await pumpEventQueue(times: 6);

      expect(recordingBloc.state.status, RecordingStatus.recording);
      expect(recordingBloc.state.segments, hasLength(2));
      expect(recordingBloc.state.activeSegmentId, 'seg_2');
      expect(recordingBloc.state.gaps.single.endedAtWallClock, isNotNull);
    },
  );
}

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
    dropFromDevice();
  }

  void dropFromDevice() {
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
  }
}

class _FakeAdapter implements BleAdapter {
  _FakeAdapter({required this.connection});

  _FakeConnection? connection;

  @override
  Future<BleConnection> connect(BleDeviceId id) async => connection!;

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

class _MemoryExperimentStorage implements ExperimentStorage {
  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
  }) async {}

  @override
  Future<void> appendSamples(List<int> samples) async {}

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {}

  @override
  Future<void> close() async {}
}

class _DelayedFlushExperimentStorage extends _MemoryExperimentStorage {
  Completer<void>? _nextDelayedFlush;
  Completer<void>? _activeDelayedFlush;

  void delayNextFlush() {
    _nextDelayedFlush = Completer<void>();
  }

  void completeDelayedFlush() {
    final delayedFlush = _activeDelayedFlush ?? _nextDelayedFlush;
    if (delayedFlush != null && !delayedFlush.isCompleted) {
      delayedFlush.complete();
    }
  }

  @override
  Future<void> flush() async {
    final delayedFlush = _nextDelayedFlush;
    if (delayedFlush == null) {
      return;
    }
    _nextDelayedFlush = null;
    _activeDelayedFlush = delayedFlush;
    await delayedFlush.future;
    _activeDelayedFlush = null;
  }
}

class _FixedIdGenerator implements ExperimentIdGenerator {
  const _FixedIdGenerator();

  @override
  String nextId() => 'exp_bridge_test';
}
