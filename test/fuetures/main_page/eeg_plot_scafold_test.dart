import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/band_power_scafold.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/eeg_plot_scafold.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/fft_plot_scafold.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: SizedBox(width: 360, height: 220, child: child)),
    );
  }

  testWidgets('signal plot clips data and disables chart animation', (
    tester,
  ) async {
    final data = List<FlSpot>.generate(32, (index) {
      final y =
          index == 8
              ? 140.0
              : index == 16
              ? -130.0
              : (index.isEven ? 18.0 : -14.0);
      return FlSpot(index.toDouble(), y);
    });

    await tester.pumpWidget(wrap(PlotScafold(data: data)));
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    // ClipRect'ов теперь два: внешний из ZoomableChart и внутренний из
    // масштабируемого scaffold fl_chart.
    expect(find.byType(ClipRect), findsWidgets);
    expect(chart.duration, Duration.zero);
    expect(chart.data.clipData, const FlClipData.all());
    expect(
      chart.data.lineBarsData.single.color,
      EegPalette.oscilloscope.signal,
    );
    expect(chart.data.extraLinesData.extraLinesOnTop, isFalse);
    expect(chart.data.extraLinesData.horizontalLines.single.y, 0);
    // Место под подписи считается по измеренной ширине самой длинной из них,
    // а не берётся константой: раньше здесь стояло 40, и на другом размере
    // окна подпись за него вылезала.
    expect(
      chart.data.titlesData.leftTitles.sideTitles.reservedSize,
      greaterThan(0),
    );
    expect(chart.transformationConfig.scaleAxis, FlScaleAxis.free);
    expect(chart.transformationConfig.transformationController, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signal plot keeps min padding so peaks avoid the frame', (
    tester,
  ) async {
    // Плоский сигнал с одиночным резким пиком: без абсолютного минимума
    // запаса относительный padding был бы крошечным и пик сел бы впритык.
    final data = List<FlSpot>.generate(
      16,
      (index) => FlSpot(index.toDouble(), index == 8 ? 3.0 : 0.0),
    );

    await tester.pumpWidget(wrap(PlotScafold(data: data, paddingFactor: 0.01)));
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.maxY, greaterThan(3.0));
    expect(chart.data.minY, lessThan(0.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('frequency plot clips data and disables chart animation', (
    tester,
  ) async {
    final data = List<FlSpot>.generate(48, (index) {
      final y =
          index == 30
              ? -80.0
              : index == 36
              ? 12.0
              : -24.0 + index / 3;
      return FlSpot(index.toDouble(), y);
    });

    await tester.pumpWidget(wrap(FrequencyPlot(data: data, maxFrequency: 40)));
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    // ClipRect'ов теперь два: внешний из ZoomableChart и внутренний из
    // масштабируемого scaffold fl_chart.
    expect(find.byType(ClipRect), findsWidgets);
    expect(chart.duration, Duration.zero);
    expect(chart.data.clipData, const FlClipData.all());
    expect(
      chart.data.lineBarsData.single.color,
      EegPalette.oscilloscope.spectrum,
    );
    expect(chart.data.extraLinesData.extraLinesOnTop, isFalse);
    expect(chart.data.extraLinesData.horizontalLines.single.y, 0);
    expect(
      chart.data.titlesData.leftTitles.sideTitles.reservedSize,
      greaterThan(0),
    );
    expect(chart.transformationConfig.scaleAxis, FlScaleAxis.free);
    expect(chart.transformationConfig.transformationController, isNotNull);
    // Резкие выбросы (провал -80, пик 12) должны помещаться в диапазон с
    // запасом — их не должно обрезать клипом.
    expect(chart.data.minY, lessThan(-80.0));
    expect(chart.data.maxY, greaterThan(12.0));
    expect(
      chart.data.lineTouchData.touchTooltipData.fitInsideVertically,
      isTrue,
    );
    expect(
      chart.data.lineTouchData.touchTooltipData.fitInsideHorizontally,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('band power plot clips fixed 0..1 range without animation', (
    tester,
  ) async {
    final delta = List<FlSpot>.generate(
      20,
      (index) => FlSpot(index.toDouble(), index == 9 ? 2.4 : 0.2),
    );
    final theta = List<FlSpot>.generate(
      20,
      (index) => FlSpot(index.toDouble(), index == 12 ? -0.8 : 0.4),
    );

    await tester.pumpWidget(
      wrap(
        BandPowerPlot(
          deltaData: delta,
          thetaData: theta,
          alphaData: const [FlSpot(0, 0.1), FlSpot(19, 0.7)],
          betaData: const [FlSpot(0, 0.2), FlSpot(19, 1.2)],
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(find.byType(ClipRect), findsOneWidget);
    expect(chart.duration, Duration.zero);
    expect(chart.data.clipData, const FlClipData.all());
    expect(chart.data.minY, 0);
    expect(chart.data.maxY, 1.0);
    expect(chart.data.lineBarsData[0].color, EegPalette.oscilloscope.delta);
    expect(chart.data.lineBarsData[1].color, EegPalette.oscilloscope.theta);
    expect(chart.data.lineBarsData[2].color, EegPalette.oscilloscope.alpha);
    expect(chart.data.lineBarsData[3].color, EegPalette.oscilloscope.beta);
    expect(chart.data.extraLinesData.extraLinesOnTop, isFalse);
    expect(chart.data.extraLinesData.horizontalLines.single.y, 0);
    expect(find.text('Delta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('компактный сигнал сохраняет оси, но теряет зум', (tester) async {
    final data = List<FlSpot>.generate(
      64,
      (index) => FlSpot(index.toDouble(), index.isEven ? 12.0 : -9.0),
    );

    await tester.pumpWidget(wrap(PlotScafold(data: data, compact: true)));
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    // Оси со значениями — то, ради чего компактный режим вообще существует.
    expect(chart.data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
    expect(chart.data.titlesData.bottomTitles.sideTitles.showTitles, isTrue);
    // Зума в сетке нет: колесо мыши прокручивает саму сетку.
    expect(chart.transformationConfig.transformationController, isNull);
    expect(chart.transformationConfig.scaleEnabled, isFalse);
    expect(chart.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('компактные ритмы держат подсказку, но без легенды', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const BandPowerPlot(
          deltaData: [FlSpot(0, 0.1), FlSpot(30, 0.4)],
          thetaData: [FlSpot(0, 0.2), FlSpot(30, 0.5)],
          alphaData: [FlSpot(0, 0.3), FlSpot(30, 0.6)],
          betaData: [FlSpot(0, 0.4), FlSpot(30, 0.7)],
          compact: true,
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    // Значения ритмов при наведении — ровно то, за чем в мозаику и смотрят.
    expect(chart.data.lineTouchData.enabled, isTrue);
    expect(chart.data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
    // Легенда съедала бы место панели, а цвета те же, что во вкладке.
    expect(find.text('Delta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('крайние подписи осей не рисуются поверх засечек', (
    tester,
  ) async {
    // Крайние подписи fl_chart рисует дополнительно к засечкам по интервалу.
    // На узкой панели последняя подпись времени налезала на предыдущую, а
    // верхняя подпись по Y обрезалась рамкой.
    final data = List<FlSpot>.generate(
      64,
      (index) => FlSpot(index.toDouble(), index.isEven ? 30.0 : -30.0),
    );

    await tester.pumpWidget(wrap(PlotScafold(data: data, compact: true)));
    await tester.pump();

    final titles =
        tester.widget<LineChart>(find.byType(LineChart)).data.titlesData;
    expect(titles.bottomTitles.sideTitles.maxIncluded, isFalse);
    expect(titles.leftTitles.sideTitles.maxIncluded, isFalse);
    expect(titles.leftTitles.sideTitles.minIncluded, isFalse);
  });

  testWidgets('место под подписи и их размер зависят от размера графика', (
    tester,
  ) async {
    // Ни одного подобранного руками пикселя: на маленьком графике подписи
    // мельче и полоса под них уже, чем на большом.
    final data = List<FlSpot>.generate(
      64,
      (index) => FlSpot(index.toDouble(), index.isEven ? 120.0 : -120.0),
    );

    Future<SideTitles> leftTitlesFor(Size size) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: PlotScafold(data: data, compact: true),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .titlesData
          .leftTitles
          .sideTitles;
    }

    final small = await leftTitlesFor(const Size(260, 150));
    final large = await leftTitlesFor(const Size(900, 500));

    expect(
      small.reservedSize,
      lessThan(large.reservedSize),
      reason: 'мелкому графику нужна более узкая полоса под подписи',
    );
  });

  testWidgets('подсказка по ритмам показывает время и все ритмы', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const BandPowerPlot(
          deltaData: [FlSpot(0, 0.1), FlSpot(95, 0.4)],
          thetaData: [FlSpot(0, 0.2), FlSpot(95, 0.5)],
          alphaData: [FlSpot(0, 0.3), FlSpot(95, 0.6)],
          betaData: [FlSpot(0, 0.4), FlSpot(95, 0.7)],
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final touchData = chart.data.lineTouchData;
    final bars = chart.data.lineBarsData;

    // Курсор попадает не в один ритм, а во все четыре: их и надо сравнивать.
    expect(touchData.touchSpotThreshold, greaterThan(10));

    // Порядок касания намеренно перепутан — в подсказке он должен быть
    // тем же, что в легенде.
    final touched = [
      LineBarSpot(bars[2], 2, bars[2].spots[1]),
      LineBarSpot(bars[0], 0, bars[0].spots[1]),
      LineBarSpot(bars[3], 3, bars[3].spots[1]),
      LineBarSpot(bars[1], 1, bars[1].spots[1]),
    ];
    final items = touchData.touchTooltipData.getTooltipItems(touched);

    expect(items, hasLength(4));
    // 95 секунд на оси X — это 01:35, время сразу видно в подсказке.
    expect(items[0]!.text, '01:35');
    expect(items[0]!.children!.single.toPlainText(), '\nDelta  0.400 отн.');
    expect(items[1]!.text, 'Theta  0.500 отн.');
    expect(items[2]!.text, 'Alpha  0.600 отн.');
    expect(items[3]!.text, 'Beta  0.700 отн.');
    expect(items[0]!.textStyle.color, isNot(bars[0].color));
    expect(items[1]!.textStyle.color, EegPalette.oscilloscope.theta);
  });
}
