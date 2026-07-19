import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/zoomable_chart.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

class FrequencyPlot extends StatefulWidget {
  final List<FlSpot> data;
  final Color? lineColor;
  final double? minY;
  final double? maxY;
  final double maxFrequency;
  final double smoothingFactor;
  final double paddingFactor;
  final bool showTooltip;

  /// Режим панели мозаики: подписи мельче, засечек меньше, зума нет.
  /// Смысл тот же, что у compact в остальных графиках.
  final bool compact;

  const FrequencyPlot({
    super.key,
    required this.data,
    this.lineColor,
    this.minY,
    this.maxY,
    this.maxFrequency = 40,
    this.smoothingFactor = 0.1,
    this.paddingFactor = 0.2,
    this.showTooltip = true,
    this.compact = false,
  });

  @override
  State<FrequencyPlot> createState() => _FrequencyPlotState();
}

class _FrequencyPlotState extends State<FrequencyPlot> {
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
    final lineColor = widget.lineColor ?? palette.spectrum;
    final validData = widget.data
        .where(
          (spot) =>
              spot.x.isFinite &&
              spot.y.isFinite &&
              spot.x >= 0 &&
              spot.x <= widget.maxFrequency,
        )
        .toList(growable: false);

    if (validData.isEmpty) {
      return Center(
        child: Text(
          'Нет данных спектра',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final yRange = _stableRangeFor(validData);
    final compact = widget.compact;
    final ticks = compact ? 3 : 5;
    final yInterval = _niceInterval(yRange.span, targetTicks: ticks);
    final xInterval = _niceInterval(widget.maxFrequency, targetTicks: ticks);
    final gridColor = palette.grid.withValues(alpha: 0.72);
    final baselineColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.34);
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: compact ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
      fontSize: compact ? 10 : 13,
      fontWeight: FontWeight.w600,
    );

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: widget.maxFrequency,
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
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            curveSmoothness: 0.15,
            spots: validData,
            dotData: const FlDotData(show: false),
            color: lineColor,
            barWidth: 2,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.22),
                  lineColor.withValues(alpha: 0.03),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: widget.showTooltip,
          touchTooltipData: LineTouchTooltipData(
            fitInsideVertically: true,
            fitInsideHorizontally: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.x.toStringAsFixed(1)} Hz\n${spot.y.toStringAsFixed(1)} dB',
                  TextStyle(color: colorScheme.onSurface, fontSize: 12),
                  textDirection: TextDirection.ltr,
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
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
              reservedSize: compact ? 22 : 30,
              getTitlesWidget:
                  (value, meta) => _AxisLabel(
                    text: '${_formatTick(value, xInterval)} Гц',
                    style: axisStyle,
                    padding: EdgeInsets.only(top: compact ? 4 : 8),
                  ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yInterval,
              reservedSize: compact ? 40 : 42,
              getTitlesWidget:
                  (value, meta) => _AxisLabel(
                    text: _formatTick(value, yInterval),
                    style: axisStyle,
                    padding: EdgeInsets.only(right: compact ? 5 : 8),
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
      ),
      duration: Duration.zero,
      transformationConfig:
          compact
              ? const FlTransformationConfig(
                scaleAxis: FlScaleAxis.none,
                panEnabled: false,
                scaleEnabled: false,
              )
              : FlTransformationConfig(
                scaleAxis: FlScaleAxis.free,
                minScale: 1,
                maxScale: 12,
                panEnabled: true,
                scaleEnabled: true,
                trackpadScrollCausesScale: true,
                transformationController: _transformController,
              ),
    );

    if (compact) {
      return ClipRect(child: ExcludeSemantics(child: chart));
    }
    return ZoomableChart(
      transformController: _transformController,
      colorScheme: colorScheme,
      child: chart,
    );
  }

  _ChartRange _stableRangeFor(List<FlSpot> validData) {
    final next = _calculateYRange(validData);
    final current = _stableYRange;
    if (current == null || _shouldAdoptRange(current, next)) {
      _stableYRange = next;
      return next;
    }
    return current;
  }

  _ChartRange _calculateYRange(List<FlSpot> validData) {
    // Диапазон по фактическим min/max всех валидных точек, чтобы резкие
    // выбросы (notch-провал вниз, острый пик вверх) помещались с запасом и
    // не обрезались клипом. Перцентили здесь не годятся — именно выбросы
    // важны для оператора.
    var dataMinY = double.infinity;
    var dataMaxY = -double.infinity;
    for (final spot in validData) {
      if (spot.y < dataMinY) dataMinY = spot.y;
      if (spot.y > dataMaxY) dataMaxY = spot.y;
    }
    if (dataMinY == dataMaxY) {
      dataMinY -= 1;
      dataMaxY += 1;
    }

    final minRange = 20.0;
    final effectiveRange = max(dataMaxY - dataMinY, minRange);
    final padding = effectiveRange * widget.paddingFactor.clamp(0.0, 1.0);
    final calculatedMin = dataMinY - padding;
    final calculatedMax = dataMaxY + padding;

    // widget.minY/maxY — только нижние границы видимости: фактический диапазон
    // с запасом имеет приоритет, если он шире (иначе выброс уехал бы за рамку).
    final floorMin = widget.minY ?? -10;
    final floorMax = widget.maxY ?? 0;
    final minY = min(calculatedMin, floorMin);
    final maxY = max(calculatedMax, floorMax);
    return _ChartRange(minY.toDouble(), maxY.toDouble());
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
        // Строго одна строка: в компактном режиме места в отведённой полосе
        // ровно на неё, а перенос уводил бы вторую строку под сам график.
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
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
