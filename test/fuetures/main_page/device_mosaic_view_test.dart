import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/device_mosaic_view.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_panel.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_plots.dart';
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
    ValueChanged<DeviceViewSession>? onStartRecording,
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
            onStartRecording: onStartRecording ?? (_) {},
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

  testWidgets('клик выбирает панель, кнопка в заголовке разворачивает', (
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

    await tester.tap(find.byTooltip('Открыть вкладкой').at(1));
    await tester.pump();
    expect(expanded, 1);
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

  testWidgets('старт записи запрашивается из панели', (tester) async {
    DeviceViewSession? started;
    final sessions = makeSessions(tester, 2);
    await pumpMosaic(
      tester,
      sessions,
      onStartRecording: (session) => started = session,
    );

    await tester.tap(find.byTooltip('Начать эксперимент').at(1));
    await tester.pump();

    expect(started, same(sessions[1]));
  });

  testWidgets('остановка записи из панели спрашивает подтверждение', (
    tester,
  ) async {
    // Промах по «стоп» обрывает многочасовой эксперимент — цена ошибки здесь
    // несопоставима с промахом по «старту».
    final sessions = makeSessions(tester, 1);
    final recordingBloc = sessions.single.recordingBloc;
    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await pumpMosaic(tester, sessions);
    await tester.pump();

    await tester.tap(find.byTooltip('Завершить запись'));
    await tester.pumpAndSettle();
    expect(find.text('Завершить эксперимент?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(
      recordingBloc.state.status,
      RecordingStatus.recording,
      reason: 'отмена не должна останавливать запись',
    );
  });

  testWidgets('метки ставятся из панели, пока идёт запись', (tester) async {
    final sessions = makeSessions(tester, 1);
    final recordingBloc = sessions.single.recordingBloc;
    await pumpMosaic(tester, sessions);

    // Записи нет — метку поставить некуда.
    expect(
      tester
          .widget<InkResponse>(
            find.descendant(
              of: find.byTooltip('Поставить метку'),
              matching: find.byType(InkResponse),
            ),
          )
          .onTap,
      isNull,
    );

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Поставить метку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Спит').last);
    await tester.pumpAndSettle();

    expect(recordingBloc.state.activeDraftLabel?.labelTypeId, 'sleep');
    // Открытое состояние видно прямо в панели, иначе метка тянулась бы
    // до конца записи незамеченной.
    expect(find.text('Спит'), findsOneWidget);
  });

  testWidgets('панель обновляется покадрово, а не раз в десятую секунды', (
    tester,
  ) async {
    // На стенде 100 мс читались как подтормаживание, хотя кадры не терялись.
    // 16 мс — чуть чаще кадра при 60 Гц: лишние перестройки срезаны, но ни
    // один кадр не пропущен.
    final sessions = makeSessions(tester, 1);
    await pumpMosaic(tester, sessions);

    final panel = tester.widget<DeviceMosaicPanel>(
      find.byType(DeviceMosaicPanel),
    );
    expect(
      panel.refreshInterval.inMilliseconds,
      lessThanOrEqualTo(16),
      reason: 'задержка не должна быть заметна глазом',
    );
  });

  testWidgets('в панели видны оси со значениями', (tester) async {
    final sessions = makeSessions(tester, 2);
    final rtBloc = sessions.first.rtEegDataBloc;
    await pumpMosaic(tester, sessions);

    for (var i = 0; i < 300; i++) {
      rtBloc.add(NewEegDataReceived(newEegData: (i % 20) - 10.0));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Оси рисует общий с вкладкой график: значения по амплитуде и время по X.
    final charts = tester.widgetList<LineChart>(find.byType(LineChart));
    expect(charts, isNotEmpty);
    for (final chart in charts) {
      expect(chart.data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
      expect(chart.data.titlesData.bottomTitles.sideTitles.showTitles, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('спектр включается в панели и остаётся у соседей выключенным', (
    tester,
  ) async {
    final sessions = makeSessions(tester, 2);
    final rtBloc = sessions.first.rtEegDataBloc;
    await pumpMosaic(tester, sessions);

    for (var i = 0; i < 400; i++) {
      rtBloc.add(NewEegDataReceived(newEegData: (i % 20) - 10.0));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byType(MosaicSpectrumPlot), findsNothing);

    await tester.tap(find.byTooltip('Показать «Спектр»').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Состав графиков у каждой панели свой: соседнюю трогать нельзя.
    expect(find.byType(MosaicSpectrumPlot), findsOneWidget);
    expect(find.byTooltip('Убрать «Спектр»'), findsOneWidget);
    expect(find.byTooltip('Показать «Спектр»'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('последний график панели выключить нельзя', (tester) async {
    // Пустая панель ничего не показывает, но место в сетке занимает.
    final sessions = makeSessions(tester, 1);
    await pumpMosaic(tester, sessions);

    await tester.tap(find.byTooltip('Убрать «Ритмы»'));
    await tester.pump();

    expect(find.byTooltip('Показать «Ритмы»'), findsOneWidget);
    expect(
      find.byTooltip('Сигнал: последний график, его не убрать'),
      findsOneWidget,
      reason: 'кнопка сама объясняет, почему не нажимается',
    );

    await tester.tap(
      find.byTooltip('Сигнал: последний график, его не убрать'),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(
      find.byTooltip('Сигнал: последний график, его не убрать'),
      findsOneWidget,
      reason: 'состав не изменился',
    );
  });

  testWidgets('пустой список не роняет мозаику', (tester) async {
    await pumpMosaic(tester, const []);

    expect(find.byType(DeviceMosaicPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
