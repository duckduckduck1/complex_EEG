import 'dart:async';

import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';

/// Фейки для тестов, которым нужна [DeviceViewSession] целиком.
///
/// Сессия связывает подключение, графики и запись, поэтому её нельзя собрать из
/// одного bloc'а записи — а нужна она сразу нескольким тестам вкладок. Держим
/// сборку в одном месте, чтобы фейк BLE не расползался по файлам копиями.
class FakeBleConnection implements BleConnection {
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
    // Настоящее устройство после отключения пакетов не шлёт — фейк тоже.
    await _packets.close();
  }
}

class FakeBleAdapter implements BleAdapter {
  @override
  Future<BleConnection> connect(BleDeviceId id) async => FakeBleConnection();

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

/// Собирает сессию на фейках. [recordingBloc] можно передать снаружи, когда
/// тесту нужно управлять записью напрямую.
DeviceViewSession createTestViewSession({
  DeviceConnectionBloc? connection,
  RecordingBloc? recordingBloc,
  String title = 'EEG-device:01',
}) {
  return DeviceViewSession(
    connection: connection ?? DeviceConnectionBloc(adapter: FakeBleAdapter()),
    recordingBloc: recordingBloc ?? createTestRecordingBloc(),
    title: title,
  );
}

RecordingBloc createTestRecordingBloc() {
  return RecordingBloc(
    storage: MemoryExperimentStorage(),
    filterFactory: const PassThroughStreamingFilterFactory(),
    idGenerator: const FixedExperimentIdGenerator(),
    fbmTransport: const FakeFbmTransport(),
  );
}

class MemoryExperimentStorage implements ExperimentStorage {
  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
    required String folderName,
  }) async {}

  @override
  Future<void> appendSamples({
    required List<int> filtered,
    required List<int> raw,
  }) async {}

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> writeReadme(String text) async {}

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {}

  @override
  Future<void> close() async {}
}

class FixedExperimentIdGenerator implements ExperimentIdGenerator {
  const FixedExperimentIdGenerator();

  @override
  String nextId() => 'exp_widget_test';
}

class FakeFbmTransport implements FbmTransport {
  const FakeFbmTransport();

  @override
  Future<bool> setLed({required bool on, required int pwmByte}) async => true;
}
