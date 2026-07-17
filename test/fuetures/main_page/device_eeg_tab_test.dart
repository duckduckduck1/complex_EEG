import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/device_eeg_tab.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';

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
}

class _FakeAdapter implements BleAdapter {
  @override
  Future<BleConnection> connect(BleDeviceId id) async => _FakeConnection();

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

void main() {
  testWidgets(
    'размонтирование вкладки не закрывает DeviceConnectionBloc сессии',
    (tester) async {
      final connectionBloc = DeviceConnectionBloc(adapter: _FakeAdapter());
      final recordingBloc = _createRecordingBloc();
      addTearDown(connectionBloc.close);
      addTearDown(() async {
        if (!recordingBloc.isClosed) {
          await recordingBloc.close();
        }
      });
      connectionBloc.add(const ConnectRequested(BleDeviceId('AA:BB:CC')));
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: DeviceEegTab(
            connection: connectionBloc,
            recordingBloc: recordingBloc,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(EegWidget), findsOneWidget);

      // Закрытие вкладки: на месте DeviceEegTab оказывается другой виджет.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // Подключением владеет SessionsCubit: вкладка его не закрывает.
      expect(connectionBloc.isClosed, isFalse);
      expect(
        connectionBloc.state.status,
        DeviceConnectionStatus.connected,
        reason: 'закрытие вкладки не должно отключать устройство',
      );
    },
  );
}

RecordingBloc _createRecordingBloc() {
  return RecordingBloc(
    storage: _MemoryExperimentStorage(),
    filterFactory: const PassThroughStreamingFilterFactory(),
    idGenerator: const _FixedIdGenerator(),
    fbmTransport: const _FakeFbmTransport(),
  );
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

class _FixedIdGenerator implements ExperimentIdGenerator {
  const _FixedIdGenerator();

  @override
  String nextId() => 'exp_widget_test';
}

class _FakeFbmTransport implements FbmTransport {
  const _FakeFbmTransport();

  @override
  Future<bool> setLed({required bool on, required int pwmByte}) async => true;
}
