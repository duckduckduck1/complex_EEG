import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/band_power_scafold.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/eeg_plot_scafold.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/fft_plot_scafold.dart';
import 'package:iot/theme.dart';

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
    expect(find.byType(ClipRect), findsOneWidget);
    expect(chart.duration, Duration.zero);
    expect(chart.data.clipData, const FlClipData.all());
    expect(
      chart.data.lineBarsData.single.color,
      EegPalette.oscilloscope.signal,
    );
    expect(chart.data.titlesData.leftTitles.sideTitles.reservedSize, 40);
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
    expect(find.byType(ClipRect), findsOneWidget);
    expect(chart.duration, Duration.zero);
    expect(chart.data.clipData, const FlClipData.all());
    expect(
      chart.data.lineBarsData.single.color,
      EegPalette.oscilloscope.spectrum,
    );
    expect(chart.data.titlesData.leftTitles.sideTitles.reservedSize, 42);
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
    expect(find.text('Delta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
