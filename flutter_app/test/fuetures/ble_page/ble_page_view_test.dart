import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/core/errors/failures.dart';
import 'package:iot/features/devices/application/sessions_cubit.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';
import 'package:iot/fuetures/ble_page/views/ble_page_view.dart';

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

/// Fake-адаптер с управляемым временем подключения: по умолчанию `connect`
/// завершается сразу, но можно подставить `Completer` на конкретный id, чтобы
/// держать соединение в фазе `connecting` до тех пор, пока тест не решит его
/// завершить (нужно для проверки нескольких параллельных сессий).
class _FakeAdapter implements BleAdapter {
  _FakeAdapter({this.connectFailure});

  final StreamController<DiscoveredDevice> _scanController =
      StreamController<DiscoveredDevice>.broadcast();
  BleFailure? connectFailure;
  final List<BleDeviceId> connectCalls = [];
  final Map<String, Completer<BleConnection>> pendingConnects = {};
  int scanCount = 0;
  String? lastNamePrefix;

  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) {
    scanCount++;
    lastNamePrefix = namePrefix;
    return _scanController.stream;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<BleConnection> connect(BleDeviceId id) {
    connectCalls.add(id);
    if (connectFailure != null) {
      return Future.error(connectFailure!);
    }
    final pending = pendingConnects[id.value];
    if (pending != null) {
      return pending.future;
    }
    return Future.value(_FakeConnection());
  }

  void emitDevice(DiscoveredDevice device) => _scanController.add(device);
}

Widget _wrap(_FakeAdapter adapter, {NavigationCubit? navigationCubit}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<SessionsCubit>(
        create: (_) => SessionsCubit(adapter: adapter),
      ),
      BlocProvider<NavigationCubit>(
        create: (_) => navigationCubit ?? NavigationCubit(),
      ),
    ],
    child: MaterialApp(home: BlePageView(adapter: adapter)),
  );
}

void main() {
  // RSSI на карточке снова отображается — осознанная отмена прежнего решения
  // «RSSI лишний» по явной просьбе Richard (2026-07-05): RSSI — признак
  // живости устройства в персистентном списке.
  testWidgets(
    'после обнаружения устройства рендерится карточка с display-именем и RSSI',
    (tester) async {
      final adapter = _FakeAdapter();
      await tester.pumpWidget(_wrap(adapter));

      await tester.tap(find.text('Искать'));
      await tester.pump();
      expect(adapter.scanCount, 1);
      expect(adapter.lastNamePrefix, 'JDY-16');

      adapter.emitDevice(
        const DiscoveredDevice(
          id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
          name: 'JDY-16',
          rssi: -42,
        ),
      );
      await tester.pump();

      expect(find.text('EEG-device:4F'), findsOneWidget);
      expect(find.text('Не подключено'), findsOneWidget);
      expect(find.text('RSSI: -42 дБм'), findsOneWidget);
      expect(find.text('AA:BB:CC:DD:EE:4F'), findsNothing);
    },
  );

  testWidgets(
    'устройство без RSSI (не подтверждено текущим поиском) показывает '
    '«Не найдено в последнем поиске»',
    (tester) async {
      final adapter = _FakeAdapter();
      await tester.pumpWidget(_wrap(adapter));

      await tester.tap(find.text('Искать'));
      await tester.pump();

      adapter.emitDevice(
        const DiscoveredDevice(
          id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
          name: 'JDY-16',
        ),
      );
      await tester.pump();

      expect(find.text('Не найдено в последнем поиске'), findsOneWidget);
      expect(find.textContaining('RSSI'), findsNothing);
    },
  );

  testWidgets(
    'карточка с активной сессией не показывает «Не найдено в последнем '
    'поиске»: подключённое устройство не рекламирует себя, отсутствие RSSI '
    'для него норма',
    (tester) async {
      final adapter = _FakeAdapter();
      await tester.pumpWidget(_wrap(adapter));

      await tester.tap(find.text('Искать'));
      await tester.pump();

      adapter.emitDevice(
        const DiscoveredDevice(
          id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
          name: 'JDY-16',
        ),
      );
      await tester.pump();
      expect(find.text('Не найдено в последнем поиске'), findsOneWidget);

      await tester.tap(find.text('EEG-device:4F'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Подключено'), findsOneWidget);
      expect(find.text('Не найдено в последнем поиске'), findsNothing);
    },
  );

  testWidgets('тап по карточке без сессии вызывает SessionsCubit.openSession', (
    tester,
  ) async {
    final adapter = _FakeAdapter();
    await tester.pumpWidget(_wrap(adapter));

    await tester.tap(find.text('Искать'));
    await tester.pump();

    const device = DiscoveredDevice(
      id: BleDeviceId('AA:BB:CC:DD:EE:01'),
      name: 'JDY-16',
    );
    adapter.emitDevice(device);
    await tester.pump();

    await tester.tap(find.text('EEG-device:01'));
    await tester.pump();
    await tester.pump();

    expect(adapter.connectCalls, [device.id]);
    expect(find.text('Подключено'), findsOneWidget);
  });

  testWidgets(
    'два устройства с открытыми сессиями видны одновременно с независимыми статусами',
    (tester) async {
      final adapter = _FakeAdapter();
      const deviceA = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:01'),
        name: 'JDY-16',
      );
      const deviceB = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:02'),
        name: 'JDY-16',
      );
      final completerA = Completer<BleConnection>();
      final completerB = Completer<BleConnection>();
      adapter.pendingConnects[deviceA.id.value] = completerA;
      adapter.pendingConnects[deviceB.id.value] = completerB;

      await tester.pumpWidget(_wrap(adapter));
      await tester.tap(find.text('Искать'));
      await tester.pump();

      adapter.emitDevice(deviceA);
      adapter.emitDevice(deviceB);
      await tester.pump();

      await tester.tap(find.text('EEG-device:01'));
      await tester.pump();
      await tester.tap(find.text('EEG-device:02'));
      await tester.pump();

      // Обе сессии одновременно в процессе подключения — независимо друг от друга.
      expect(find.text('Подключение…'), findsNWidgets(2));

      completerA.complete(_FakeConnection());
      await tester.pump();
      await tester.pump();

      // A подключилось, B всё ещё подключается — статусы не связаны.
      expect(find.text('Подключено'), findsOneWidget);
      expect(find.text('Подключение…'), findsOneWidget);

      completerB.complete(_FakeConnection());
      await tester.pump();
      await tester.pump();

      expect(find.text('Подключено'), findsNWidgets(2));
    },
  );

  testWidgets(
    'NavigationCubit.openDevicesAndStartScan запускает поиск и сбрасывает флаг',
    (tester) async {
      final adapter = _FakeAdapter();
      final navigationCubit = NavigationCubit();

      await tester.pumpWidget(_wrap(adapter, navigationCubit: navigationCubit));
      await tester.pump();

      expect(adapter.connectCalls, isEmpty);

      navigationCubit.openDevicesAndStartScan();
      await tester.pump();
      await tester.pump();

      expect(adapter.scanCount, 1);
      expect(adapter.lastNamePrefix, 'JDY-16');
      expect(find.text('Стоп'), findsOneWidget);
      expect(navigationCubit.state.autoStartDiscoveryRequested, isFalse);
    },
  );

  testWidgets(
    'после подключения показывается SnackBar; кнопка «Открыть график» '
    'выставляет pendingTab и переключает на «Главная»',
    (tester) async {
      final adapter = _FakeAdapter();
      final navigationCubit = NavigationCubit();
      // Стартуем не с «Главной», чтобы увидеть реальное переключение раздела.
      navigationCubit.selectSection(1);

      await tester.pumpWidget(_wrap(adapter, navigationCubit: navigationCubit));
      await tester.tap(find.text('Искать'));
      await tester.pump();

      const device = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:4F'),
        name: 'JDY-16',
      );
      // Удерживаем подключение в фазе connecting, чтобы карточка с сессией
      // успела построиться и подписаться до перехода в connected — как на
      // реальном устройстве, где подключение не мгновенно.
      final completer = Completer<BleConnection>();
      adapter.pendingConnects[device.id.value] = completer;
      adapter.emitDevice(device);
      await tester.pump();

      await tester.tap(find.text('EEG-device:4F'));
      await tester.pump();
      expect(find.text('Подключение…'), findsOneWidget);

      completer.complete(_FakeConnection());
      await tester.pump();
      await tester.pump();

      expect(find.text('Устройство EEG-device:4F подключено'), findsOneWidget);

      // Дожидаемся конца входной анимации снекбара, иначе тап не попадёт.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Открыть график'));
      await tester.pump();

      expect(navigationCubit.state.pendingTabDeviceId, device.id);
      expect(navigationCubit.state.sectionIndex, 0);

      // Дожидаемся скрытия снекбара, чтобы не осталось активных таймеров.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'снекбар показывается один раз на подключение и не дублируется на ребилдах',
    (tester) async {
      final adapter = _FakeAdapter();
      await tester.pumpWidget(_wrap(adapter));
      await tester.tap(find.text('Искать'));
      await tester.pump();

      const device = DiscoveredDevice(
        id: BleDeviceId('AA:BB:CC:DD:EE:01'),
        name: 'JDY-16',
      );
      final completer = Completer<BleConnection>();
      adapter.pendingConnects[device.id.value] = completer;
      adapter.emitDevice(device);
      await tester.pump();

      await tester.tap(find.text('EEG-device:01'));
      await tester.pump();
      completer.complete(_FakeConnection());
      await tester.pump();
      await tester.pump();

      expect(find.text('Открыть график'), findsOneWidget);

      // Ребилд списка (обнаружено ещё одно устройство) не должен показать
      // снекбар повторно: статус подключения первой сессии не менялся.
      adapter.emitDevice(
        const DiscoveredDevice(
          id: BleDeviceId('AA:BB:CC:DD:EE:02'),
          name: 'JDY-16',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Открыть график'), findsOneWidget);

      // Дожидаемся скрытия снекбара: конец входной анимации, таймер показа
      // (4 с) и выходная анимация — чтобы не осталось активных таймеров.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Открыть график'), findsNothing);
    },
  );

  testWidgets('состояние failed показывает безопасный текст ошибки', (
    tester,
  ) async {
    final adapter = _FakeAdapter(
      connectFailure: BleFailure.connectionFailed(cause: 'boom'),
    );
    await tester.pumpWidget(_wrap(adapter));

    await tester.tap(find.text('Искать'));
    await tester.pump();

    const device = DiscoveredDevice(
      id: BleDeviceId('AA:BB:CC:DD:EE:01'),
      name: 'JDY-16',
    );
    adapter.emitDevice(device);
    await tester.pump();

    await tester.tap(find.text('EEG-device:01'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Не удалось подключиться к устройству.'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('Переподключиться'), findsOneWidget);
  });
}
