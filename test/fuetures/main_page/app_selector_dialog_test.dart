import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/device_session.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/sessions_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/navigation/navigation_cubit.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/widgets/app_selector_diolog.dart';

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
    // Настоящее устройство после отключения пакетов не шлёт — фейк тоже.
    await _packets.close();
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
  late SessionsCubit sessionsCubit;
  late NavigationCubit navigationCubit;

  setUp(() {
    sessionsCubit = SessionsCubit(adapter: _FakeAdapter());
    navigationCubit = NavigationCubit();
  });

  tearDown(() async {
    await navigationCubit.close();
    await sessionsCubit.close();
  });

  Widget buildApp(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SessionsCubit>.value(value: sessionsCubit),
        BlocProvider<NavigationCubit>.value(value: navigationCubit),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets(
    'пустой список сессий: кнопка "Подключиться" запускает переход на '
    'экран устройств и закрывает диалог без результата',
    (tester) async {
      DeviceSession? result;
      await tester.pumpWidget(
        buildApp(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showAppSelectorDialog(context);
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Нет подключённых устройств'), findsOneWidget);

      await tester.tap(find.text('Подключиться'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(navigationCubit.state.sectionIndex, 1);
      expect(navigationCubit.state.autoStartDiscoveryRequested, isTrue);
    },
  );

  testWidgets(
    'непустой список сессий: показываются пункты с display-именем, тап '
    'закрывает диалог с DeviceSession для соответствующего устройства',
    (tester) async {
      const deviceA = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
        name: 'JDY-16-A',
      );
      const deviceB = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:02'),
        name: 'JDY-16-B',
      );
      sessionsCubit.openSession(deviceA);
      sessionsCubit.openSession(deviceB);

      DeviceSession? result;
      await tester.pumpWidget(
        buildApp(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showAppSelectorDialog(context);
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      );
      // Даём завершиться Future от _FakeAdapter.connect() внутри openSession.
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EEG-device:4F'), findsOneWidget);
      expect(find.text('EEG-device:02'), findsOneWidget);

      await tester.tap(find.text('EEG-device:4F'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(result, isNotNull);
      expect(result!.deviceId, deviceA.id);
      expect(
        result!.connection,
        same(sessionsCubit.sessionFor(deviceA.id)!.connection),
      );
    },
  );
}
