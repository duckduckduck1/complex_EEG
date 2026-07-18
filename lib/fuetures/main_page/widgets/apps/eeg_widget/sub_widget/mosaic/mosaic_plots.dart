import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_decimation.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

/// Графики для панели мозаики — раздетые до линии.
///
/// От графиков вкладки отличаются намеренно: ни осей, ни подписей, ни зума, ни
/// касаний. На панели 380×230 подписи занимают больше места, чем сам сигнал, а
/// разглядывать значения оператор всё равно уходит во вкладку. Мозаика отвечает
/// на один вопрос — «как там все десять», — и всё, что не помогает ответить,
/// убрано ради скорости отрисовки.

/// Сигнал одного устройства.
class MosaicSignalPlot extends StatelessWidget {
  const MosaicSignalPlot({super.key, required this.data, this.isLive = true});

  final List<FlSpot> data;

  /// Нет связи — линия гаснет до серой, чтобы замерший график не выглядел живым.
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<EegPalette>() ?? EegPalette.oscilloscope;
    final color =
        isLive
            ? palette.signal
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Прореживаем под ту ширину, в которую реально рисуем: больше точек,
        // чем пикселей, всё равно не увидеть.
        final spots = decimateMinMax(data, constraints.maxWidth.round());
        if (spots.isEmpty) {
          return const _WaitingForSignal();
        }

        final minY = spots.map((spot) => spot.y).reduce(min);
        final maxY = spots.map((spot) => spot.y).reduce(max);
        final padding = max((maxY - minY) * 0.2, 1.0);

        return RepaintBoundary(
          child: ExcludeSemantics(
            child: LineChart(
              LineChartData(
                minX: spots.first.x,
                maxX: spots.last.x,
                minY: minY - padding,
                maxY: maxY + padding,
                clipData: const FlClipData.all(),
                titlesData: const FlTitlesData(show: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    color: color,
                    barWidth: 1.2,
                    isCurved: false,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        );
      },
    );
  }
}

/// Ритмы одного устройства: четыре линии в диапазоне 0..1 без подписей.
///
/// Точка добавляется раз в секунду и хранится их 60, поэтому прореживать тут
/// нечего — график дешёвый и на панели помещается целиком.
class MosaicBandsPlot extends StatelessWidget {
  const MosaicBandsPlot({
    super.key,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
  });

  final List<FlSpot> delta;
  final List<FlSpot> theta;
  final List<FlSpot> alpha;
  final List<FlSpot> beta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<EegPalette>() ?? EegPalette.oscilloscope;
    final all = [...delta, ...theta, ...alpha, ...beta];
    if (all.isEmpty) {
      return const _WaitingForSignal();
    }

    final minX = all.map((spot) => spot.x).reduce(min);
    final maxX = max(all.map((spot) => spot.x).reduce(max), minX + 1);

    return RepaintBoundary(
      child: ExcludeSemantics(
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: 0,
            maxY: 1,
            clipData: const FlClipData.all(),
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              _bar(delta, palette.delta),
              _bar(theta, palette.theta),
              _bar(alpha, palette.alpha),
              _bar(beta, palette.beta),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    color: color,
    barWidth: 1.4,
    isCurved: false,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: false),
  );
}

class _WaitingForSignal extends StatelessWidget {
  const _WaitingForSignal();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'ждём сигнал',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
      ),
    );
  }
}
