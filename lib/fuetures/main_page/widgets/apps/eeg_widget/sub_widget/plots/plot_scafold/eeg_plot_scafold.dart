import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/zoomable_chart.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

class PlotScafold extends StatefulWidget {
  final List<FlSpot> data;
  final double minY;
  final double maxY;
  final double paddingFactor; // Множитель для отступа (0.1 = 10%)
  final int? visibleTimeSeconds; // Видимое время в секундах (опционально)
  const PlotScafold({
    super.key,
    required this.data,
    this.maxY = 2,
    this.minY = -2,
    this.paddingFactor = 0.1,
    this.visibleTimeSeconds,
  });

  @override
  State<PlotScafold> createState() => _PlotScafoldState();
}

const double _minPadding = 2.5;

class _PlotScafoldState extends State<PlotScafold> {
  _ChartRange? _stableYRange;
  late final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = theme.extension<EegPalette>() ?? EegPalette.oscilloscope;
    final validData = widget.data
        .where((spot) => spot.x.isFinite && spot.y.isFinite)
        .toList(growable: false);

    if (validData.isEmpty) {
      return Center(
        child: Text(
          'Нет данных сигнала',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final yRange = _stableRangeFor(validData);
    final minX = validData.first.x;
    final maxX = max(validData.last.x, minX + 1);
    final yInterval = _niceInterval(yRange.span);
    final xInterval = _niceInterval(maxX - minX);
    final gridColor = palette.grid.withValues(alpha: 0.72);
    final baselineColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.34);
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    return ZoomableChart(
      transformController: _transformController,
      colorScheme: colorScheme,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: yRange.min,
          maxY: yRange.max,
          clipData: const FlClipData.all(),
          extraLinesData: ExtraLinesData(
            extraLinesOnTop: false,
            horizontalLines: [
              if (yRange.min <= 0 && yRange.max >= 0)
                HorizontalLine(y: 0, color: baselineColor, strokeWidth: 1.1),
            ],
          ),
          lineTouchData: const LineTouchData(handleBuiltInTouches: false),
          gridData: FlGridData(
            show: true,
            verticalInterval: xInterval,
            horizontalInterval: yInterval,
            getDrawingVerticalLine:
                (value) => FlLine(color: gridColor, strokeWidth: 0.8),
            getDrawingHorizontalLine:
                (value) => FlLine(color: gridColor, strokeWidth: 0.8),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: xInterval,
                reservedSize: 28,
                getTitlesWidget:
                    (value, meta) => _AxisLabel(
                      text: formatClock(value.round()),
                      style: axisStyle,
                      padding: const EdgeInsets.only(top: 8),
                    ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: yInterval,
                reservedSize: 40,
                getTitlesWidget:
                    (value, meta) => _AxisLabel(
                      text: _formatTick(value, yInterval),
                      style: axisStyle,
                      padding: const EdgeInsets.only(right: 8),
                      alignRight: true,
                    ),
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: validData,
              dotData: const FlDotData(show: false),
              color: palette.signal,
              barWidth: 2.2,
              isCurved: false,
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.signal.withValues(alpha: 0.22),
                    palette.signal.withValues(alpha: 0.03),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
        transformationConfig: FlTransformationConfig(
          scaleAxis: FlScaleAxis.free,
          minScale: 1,
          maxScale: 12,
          panEnabled: true,
          scaleEnabled: true,
          trackpadScrollCausesScale: true,
          transformationController: _transformController,
        ),
      ),
    );
  }

  _ChartRange _stableRangeFor(List<FlSpot> data) {
    final next = _calculateYRange(data);
    final current = _stableYRange;
    if (current == null || _shouldAdoptRange(current, next)) {
      _stableYRange = next;
      return next;
    }
    return current;
  }

  _ChartRange _calculateYRange(List<FlSpot> data) {
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final spot in data) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }

    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    final span = max(maxY - minY, 1);
    // Запас по Y: относительный от размаха, но не меньше абсолютного минимума,
    // чтобы резкие пики не сидели впритык к рамке.
    final padding = max(
      span * widget.paddingFactor.clamp(0.0, 1.0),
      _minPadding,
    );
    return _ChartRange(minY - padding, maxY + padding);
  }

  bool _shouldAdoptRange(_ChartRange current, _ChartRange next) {
    final currentSpan = max(current.span, 1e-9);
    final escapesCurrent = next.min < current.min || next.max > current.max;
    final minDrift = (next.min - current.min).abs() / currentSpan;
    final maxDrift = (next.max - current.max).abs() / currentSpan;
    final spanDrift = (next.span - current.span).abs() / currentSpan;
    return escapesCurrent ||
        minDrift > 0.08 ||
        maxDrift > 0.08 ||
        spanDrift > 0.08;
  }
}

class _ChartRange {
  final double min;
  final double max;

  const _ChartRange(this.min, this.max);

  double get span => max - min;
}

class _AxisLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final EdgeInsets padding;
  final bool alignRight;

  const _AxisLabel({
    required this.text,
    required this.style,
    required this.padding,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.center,
        style: style,
      ),
    );
  }
}

double _niceInterval(double range, {int targetTicks = 5}) {
  if (!range.isFinite || range <= 0) return 1;
  final rawInterval = range / max(targetTicks - 1, 1);
  final exponent = pow(10, (log(rawInterval) / ln10).floor()).toDouble();
  final fraction = rawInterval / exponent;
  final niceFraction =
      fraction <= 1
          ? 1
          : fraction <= 2
          ? 2
          : fraction <= 5
          ? 5
          : 10;
  return niceFraction * exponent;
}

String _formatTick(double value, double interval) {
  final digits =
      interval >= 1
          ? 0
          : interval >= 0.1
          ? 1
          : 2;
  final normalized = value.abs() < interval * 0.001 ? 0.0 : value;
  return normalized.toStringAsFixed(digits);
}
