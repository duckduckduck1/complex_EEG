import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/device_eeg_tab.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';

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
      addTearDown(connectionBloc.close);
      connectionBloc.add(const ConnectRequested(BleDeviceId('AA:BB:CC')));
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(home: DeviceEegTab(connection: connectionBloc)),
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
