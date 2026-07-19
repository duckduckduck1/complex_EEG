import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_layout/thrid_hight_layout.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('filter block stays compact and leaves space for plots', (
    tester,
  ) async {
    const firstPlotKey = Key('first-plot');

    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 600,
          height: 500,
          child: EegLayout(
            isFiltterShowing: true,
            fillterWidget: SizedBox(height: 400, child: Text('filters')),
            firtsWidget: ColoredBox(key: firstPlotKey, color: Colors.red),
            secondWidget: ColoredBox(color: Colors.green),
            thirdWidget: ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();

    final filterViewport = tester.getSize(find.byType(SingleChildScrollView));
    final firstPlot = tester.getSize(find.byKey(firstPlotKey));

    expect(find.text('Сигнал ЭЭГ'), findsOneWidget);
    expect(find.text('мкВ · 250 Гц'), findsOneWidget);
    expect(find.text('Спектр'), findsOneWidget);
    expect(find.text('Ритмы'), findsOneWidget);
    expect(filterViewport.height, lessThanOrEqualTo(156));
    expect(firstPlot.height, greaterThan(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout without filters does not add filter scroll area', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 600,
          height: 500,
          child: EegLayout(
            isFiltterShowing: false,
            firtsWidget: ColoredBox(color: Colors.red),
            secondWidget: ColoredBox(color: Colors.green),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom graph panels fit on narrow width', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 360,
          height: 560,
          child: EegLayout(
            isFiltterShowing: false,
            firtsWidget: ColoredBox(color: Colors.red),
            secondWidget: ColoredBox(color: Colors.green),
            thirdWidget: ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );

    expect(find.text('Сигнал ЭЭГ'), findsOneWidget);
    expect(find.text('Спектр'), findsOneWidget);
    expect(find.text('Ритмы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
