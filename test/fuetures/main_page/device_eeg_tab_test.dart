import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/device_eeg_tab.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/tab_active_scope.dart';

import '../../support/device_view_session_fakes.dart';

void main() {
  testWidgets('уход вкладки с экрана не рвёт ни запись, ни подключение', (
    tester,
  ) async {
    // Главная гарантия слайса: вид можно снять с экрана (закрыть вкладку,
    // переключиться на мозаику), и это не должно трогать ни идущую запись,
    // ни устройство. Владеет всем DeviceViewSession, а не виджет.
    final connectionBloc = DeviceConnectionBloc(adapter: FakeBleAdapter());
    final session = createTestViewSession(connection: connectionBloc);
    addTearDown(connectionBloc.close);
    addTearDown(session.dispose);
    connectionBloc.add(const ConnectRequested(BleDeviceId('AA:BB:CC')));
    await tester.pump();

    // Без TabActiveScope вкладка считается активной — строит график.
    await tester.pumpWidget(MaterialApp(home: DeviceEegTab(session: session)));
    await tester.pump();
    expect(find.byType(EegWidget), findsOneWidget);

    // Вкладка уходит из дерева: на её месте оказывается другой виджет.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(
      session.recordingBloc.isClosed,
      isFalse,
      reason: 'запись не должна обрываться из-за ухода вида с экрана',
    );
    expect(session.rtEegDataBloc.isClosed, isFalse);
    // Подключением владеет SessionsCubit: вкладка его не закрывает.
    expect(connectionBloc.isClosed, isFalse);
    expect(
      connectionBloc.state.status,
      DeviceConnectionStatus.connected,
      reason: 'закрытие вкладки не должно отключать устройство',
    );
  });

  testWidgets('неактивная вкладка показывает заглушку вместо графика', (
    tester,
  ) async {
    final session = createTestViewSession();
    addTearDown(session.connection.close);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TabActiveScope(
          active: false,
          child: DeviceEegTab(session: session),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(EegWidget), findsNothing);
    expect(find.textContaining('на паузе'), findsOneWidget);
  });
}
