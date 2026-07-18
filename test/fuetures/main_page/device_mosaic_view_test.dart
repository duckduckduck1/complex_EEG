import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/device_mosaic_view.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_panel.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

import '../../support/device_view_session_fakes.dart';

void main() {
  List<DeviceViewSession> makeSessions(WidgetTester tester, int count) {
    final sessions = [
      for (var i = 0; i < count; i++)
        createTestViewSession(title: 'Мышь ${i + 1}'),
    ];
    addTearDown(() async {
      for (final session in sessions) {
        await session.dispose();
        await session.connection.close();
      }
    });
    return sessions;
  }

  /// Мозаика меряется по настоящему окну, поэтому и в тесте задаём размер
  /// поверхности, а не заворачиваем её в SizedBox: панели за краями поверхности
  /// просто не попадают под нажатие.
  Future<void> pumpMosaic(
    WidgetTester tester,
    List<DeviceViewSession> sessions, {
    int selectedIndex = 0,
    ValueChanged<int>? onSelected,
    ValueChanged<int>? onExpand,
    Size size = const Size(1900, 950),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: DeviceMosaicView(
            sessions: sessions,
            selectedIndex: selectedIndex,
            onSelected: onSelected ?? (_) {},
            onExpand: onExpand ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('десять устройств показываются десятью панелями', (tester) async {
    final sessions = makeSessions(tester, 10);
    await pumpMosaic(tester, sessions);

    expect(find.byType(DeviceMosaicPanel), findsNWidgets(10));
    expect(find.text('Мышь 1'), findsOneWidget);
    expect(find.text('Мышь 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('клик по панели выбирает её, двойной — разворачивает', (
    tester,
  ) async {
    int? selected;
    int? expanded;
    final sessions = makeSessions(tester, 4);
    await pumpMosaic(
      tester,
      sessions,
      onSelected: (index) => selected = index,
      onExpand: (index) => expanded = index,
    );

    await tester.tap(find.byType(DeviceMosaicPanel).at(2));
    await tester.pump();
    expect(selected, 2);

    // Между тапами должно пройти не меньше kDoubleTapMinTime (40 мс), иначе
    // распознаватель второй тап отбросит, и это будут два одиночных клика.
    await tester.tap(find.byType(DeviceMosaicPanel).at(1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(DeviceMosaicPanel).at(1));
    await tester.pump();
    expect(expanded, 1);

    // Распознаватель двойного клика оставляет за собой таймеры — досматриваем
    // их до конца, иначе тест падает на pending timer.
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('панели не сжимаются ниже читаемой высоты, а прокручиваются', (
    tester,
  ) async {
    // Десять устройств на невысоком окне: сетка обязана уехать в прокрутку,
    // а не превратить панели в нечитаемые марки.
    final sessions = makeSessions(tester, 10);
    await pumpMosaic(tester, sessions, size: const Size(1350, 620));

    final panelSize = tester.getSize(find.byType(DeviceMosaicPanel).first);
    expect(panelSize.height, greaterThanOrEqualTo(200));
    expect(panelSize.width, greaterThanOrEqualTo(260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('пустой список не роняет мозаику', (tester) async {
    await pumpMosaic(tester, const []);

    expect(find.byType(DeviceMosaicPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
