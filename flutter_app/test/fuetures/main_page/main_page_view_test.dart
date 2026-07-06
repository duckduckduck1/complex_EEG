import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/devices/application/sessions_cubit.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/application/recording_bloc_factory.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';
import 'package:iot/fuetures/main_page/views/main_page_view.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/device_eeg_tab.dart';

class _FakeConnection implements BleConnection {
  late final StreamController<List<int>> _packets;
  final Completer<void> _disconnected = Completer<void>();
  int packetListenCount = 0;
  int packetCancelCount = 0;

  _FakeConnection() {
    _packets = StreamController<List<int>>.broadcast(
      onListen: () => packetListenCount++,
      onCancel: () => packetCancelCount++,
    );
  }

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

  Future<void> close() => _packets.close();
}

class _FakeAdapter implements BleAdapter {
  final Map<BleDeviceId, _FakeConnection> connections = {};

  @override
  Future<BleConnection> connect(BleDeviceId id) async =>
      connections.putIfAbsent(id, _FakeConnection.new);

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}

  _FakeConnection connectionFor(BleDeviceId id) => connections[id]!;

  Future<void> close() async {
    for (final connection in connections.values) {
      await connection.close();
    }
  }
}

List<int> _encodeSample(int adcValue) {
  final unsigned = adcValue < 0 ? adcValue + (1 << 18) : adcValue;
  final b0 = (unsigned >> 10) & 0xff;
  final b1 = (unsigned >> 2) & 0xff;
  final b2 = (unsigned << 6) & 0xff;
  return [b0, b1, b2];
}

void main() {
  late _FakeAdapter adapter;
  late SessionsCubit sessionsCubit;
  late NavigationCubit navigationCubit;

  setUp(() {
    adapter = _FakeAdapter();
    sessionsCubit = SessionsCubit(adapter: adapter);
    navigationCubit = NavigationCubit();
  });

  tearDown(() async {
    await navigationCubit.close();
    await sessionsCubit.close();
    await adapter.close();
  });

  Widget buildApp() {
    return RepositoryProvider<RecordingBlocFactory>(
      create: (_) => const _FakeRecordingBlocFactory(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionsCubit>.value(value: sessionsCubit),
          BlocProvider<NavigationCubit>.value(value: navigationCubit),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
  }

  testWidgets('header uses compact oscilloscope app chrome', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));

    expect(appBar.toolbarHeight, 58);
    expect(appBar.leadingWidth, 56);
    expect(appBar.titleSpacing, 0);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('device tabs use compact browser-like tab bar', (tester) async {
    const device = DiscoveredDevice(
      id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
      name: 'JDY-16',
    );
    sessionsCubit.openSession(device);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    navigationCubit.setPendingTab(device.id);
    await tester.pump();
    await tester.pump();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));

    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
    expect(tabBar.indicatorSize, TabBarIndicatorSize.label);
    expect(tabBar.indicatorWeight, 4);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
    'setPendingTab с существующей сессией создаёт вкладку и сбрасывает флаг',
    (tester) async {
      const device = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
        name: 'JDY-16',
      );
      sessionsCubit.openSession(device);
      await tester.pumpWidget(buildApp());
      await tester.pump();

      navigationCubit.setPendingTab(device.id);
      await tester.pump();
      await tester.pump();

      // Вкладка названа display-именем устройства, содержимое — DeviceEegTab.
      expect(find.text('EEG-device:4F'), findsOneWidget);
      expect(find.byType(DeviceEegTab), findsOneWidget);
      expect(navigationCubit.state.pendingTabDeviceId, isNull);
    },
  );

  testWidgets(
    'setPendingTab без сессии не создаёт вкладку, но сбрасывает флаг',
    (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      navigationCubit.setPendingTab(const BleDeviceId('AA:BB:CC:DD:EE:02'));
      await tester.pump();
      await tester.pump();

      expect(find.text('EEG-device:02'), findsNothing);
      expect(find.byType(DeviceEegTab), findsNothing);
      expect(navigationCubit.state.pendingTabDeviceId, isNull);
    },
  );

  testWidgets('кнопка "+" с выбором устройства называет вкладку display-именем '
      'устройства, а не "Tab n"', (tester) async {
    const device = DiscoveredDevice(
      id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
      name: 'JDY-16',
    );
    sessionsCubit.openSession(device);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('EEG-device:4F'));
    await tester.pumpAndSettle();

    expect(find.text('EEG-device:4F'), findsOneWidget);
    expect(find.textContaining('Tab '), findsNothing);
    expect(find.byType(DeviceEegTab), findsOneWidget);
  });

  testWidgets('переключение между EEG-вкладками не размонтирует живой график', (
    tester,
  ) async {
    // Табы теперь в строке названия аппбара; на узком стандартном окне (800px)
    // они уходят под область названия и tap по ярлыку промахивается. Даём окну
    // ширину рабочего стенда, чтобы название, разделитель и оба таба помещались
    // в одну строку и ярлык таба был кликабелен.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const deviceA = DiscoveredDevice(
      id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
      name: 'JDY-16-A',
    );
    const deviceB = DiscoveredDevice(
      id: BleDeviceId('AA:BB:CC:DD:EE:50'),
      name: 'JDY-16-B',
    );
    sessionsCubit.openSession(deviceA);
    sessionsCubit.openSession(deviceB);
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    navigationCubit.setPendingTab(deviceA.id);
    await tester.pump();
    await tester.pump();
    final connectionA = adapter.connectionFor(deviceA.id);
    expect(connectionA.packetListenCount, 1);

    navigationCubit.setPendingTab(deviceB.id);
    await tester.pump();
    await tester.pump();
    final connectionB = adapter.connectionFor(deviceB.id);
    expect(connectionB.packetListenCount, 1);
    expect(find.byType(DeviceEegTab, skipOffstage: false), findsNWidgets(2));
    expect(connectionA.packetCancelCount, 0);

    connectionA.addPayload(_encodeSample(42));
    await tester.pump();
    await tester.tap(find.text('EEG-device:4F'));
    await tester.pump();

    expect(connectionA.packetCancelCount, 0);
    expect(connectionB.packetCancelCount, 0);
  });
}

class _FakeRecordingBlocFactory implements RecordingBlocFactory {
  const _FakeRecordingBlocFactory();

  @override
  RecordingBloc create() {
    return RecordingBloc(
      storage: _MemoryExperimentStorage(),
      filterFactory: const PassThroughStreamingFilterFactory(),
      idGenerator: const _FixedIdGenerator(),
    );
  }
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
  String nextId() => 'exp_main_page_test';
}
