import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/chart_axis.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

/// Порядок ритмов: он же порядок полос в `lineBarsData`, легенды и тултипа.
/// `barIndex` из fl_chart — индекс в этом списке.
const _bandNames = ['Delta', 'Theta', 'Alpha', 'Beta'];

class BandPowerPlot extends StatelessWidget {
  final List<FlSpot> deltaData;
  final List<FlSpot> thetaData;
  final List<FlSpot> alphaData;
  final List<FlSpot> betaData;
  final double maxFrequency;
  final Color? deltaColor;
  final Color? thetaColor;
  final Color? alphaColor;
  final Color? betaColor;

  /// Режим панели мозаики: без легенды, подписи мельче, засечек меньше.
  /// Подсказка при наведении остаётся — ради значений ритмов в мозаику и
  /// смотрят.
  final bool compact;

  const BandPowerPlot({
    super.key,
    required this.deltaData,
    required this.thetaData,
    required this.alphaData,
    required this.betaData,
    this.maxFrequency = 60,
    this.deltaColor,
    this.thetaColor,
    this.alphaColor,
    this.betaColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Размер нужен до сборки графика: от него считаются шрифт подписей, место
    // под них, число засечек и размер подсказки.
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.biggest),
    );
  }

  Widget _build(BuildContext context, Size chartSize) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = theme.extension<EegPalette>() ?? EegPalette.oscilloscope;
    final colors = (
      delta: deltaColor ?? palette.delta,
      theta: thetaColor ?? palette.theta,
      alpha: alphaColor ?? palette.alpha,
      beta: betaColor ?? palette.beta,
    );
    final allData = [...deltaData, ...thetaData, ...alphaData, ...betaData];
    final minX =
        allData.isNotEmpty ? allData.map((spot) => spot.x).reduce(min) : 0.0;
    final maxX =
        allData.isNotEmpty
            ? allData.map((spot) => spot.x).reduce(max)
            : maxFrequency;
    final ensuredMaxX = max(maxX, minX + 1);
    final gridColor = palette.grid.withValues(alpha: 0.72);
    final baselineColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.34);

    final axis = ChartAxis.of(context, chartSize);
    final axisStyle = axis.labelStyle.copyWith(
      color: compact ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
    );
    // Ось Y тут всегда 0..1, поэтому самая длинная подпись известна заранее.
    const yLabel = '0.0';
    final xLabel = formatClock(ensuredMaxX.round());
    final xInterval = _niceInterval(
      ensuredMaxX - minX,
      targetTicks: axis.ticksAlong(Axis.horizontal, xLabel),
    );
    final yInterval = _niceInterval(
      1,
      targetTicks: axis.ticksAlong(Axis.vertical, yLabel),
    );

    // Подсказка живёт по тем же правилам, что подписи: размер от размера
    // графика, ширина окошка — по измеренной строке, а не по умолчанию.
    final tooltipStyle = axis.labelStyle.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: (axis.labelStyle.fontSize ?? 11) + 1,
    );
    final tooltipFontSize = tooltipStyle.fontSize!;
    final tooltipWidth =
        axis.measure('Theta  0.000 отн.', style: tooltipStyle).width + 4;

    return Column(
      children: [
        // Легенда в мозаике не нужна: цвета те же, что во вкладке, а место на
        // панели дороже. Названия ритмов всё равно видны в подсказке.
        if (!compact) ...[
          _Legend(
            items: [
              _LegendItemData(colors.delta, _bandNames[0]),
              _LegendItemData(colors.theta, _bandNames[1]),
              _LegendItemData(colors.alpha, _bandNames[2]),
              _LegendItemData(colors.beta, _bandNames[3]),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          // Скрыт от дерева доступности по той же причине, что и остальные
          // графики: узлы пересоздаются на каждый кадр и ломают AXTree.
          child: ExcludeSemantics(
            child: ClipRect(
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: ensuredMaxX,
                  minY: 0,
                  maxY: 1.0,
                  clipData: const FlClipData.all(),
                  extraLinesData: ExtraLinesData(
                    extraLinesOnTop: false,
                    horizontalLines: [
                      HorizontalLine(
                        y: 0,
                        color: baselineColor,
                        strokeWidth: 1.1,
                      ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    // Ритмы лежат на общей сетке по времени, поэтому под
                    // курсором должны отзываться все четыре, а не только
                    // ближайший: сравнивать их между собой и есть смысл графика.
                    touchSpotThreshold: 40,
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideVertically: true,
                      fitInsideHorizontally: true,
                      // Ширину окошка меряем по самой длинной строке, а не
                      // держим умолчание в 120 пикселей: на панели мозаики
                      // «Theta 0.593 отн.» в него не помещалось и обрезалось.
                      maxContentWidth: tooltipWidth,
                      tooltipPadding: EdgeInsets.symmetric(
                        horizontal: tooltipFontSize * 0.7,
                        vertical: tooltipFontSize * 0.45,
                      ),
                      getTooltipItems:
                          (touchedSpots) => _buildTooltipItems(
                            touchedSpots,
                            headerStyle: tooltipStyle.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            bodyStyle: tooltipStyle,
                          ),
                    ),
                  ),
                  lineBarsData: [
                    _buildLineBar(deltaData, colors.delta),
                    _buildLineBar(thetaData, colors.theta),
                    _buildLineBar(alphaData, colors.alpha),
                    _buildLineBar(betaData, colors.beta),
                  ],
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: xInterval,
                        reservedSize: axis.reservedBottom(xLabel),
                        // Крайняя подпись рисуется сверх засечек по интервалу
                        // и налезала на соседнюю у правого края.
                        maxIncluded: false,
                        getTitlesWidget:
                            (value, meta) => chartAxisLabel(
                              meta: meta,
                              text: formatClock(value.round()),
                              style: axisStyle,
                            ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: yInterval,
                        reservedSize: axis.reservedLeft(const [yLabel]),
                        // Верхняя «1.0» упиралась в край и обрезалась.
                        maxIncluded: false,
                        getTitlesWidget:
                            (value, meta) => chartAxisLabel(
                              meta: meta,
                              text: _formatTick(value, yInterval),
                              style: axisStyle,
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
                  borderData: FlBorderData(show: false),
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Тултип читается как «что было в этот момент»: сверху время по оси X,
  /// ниже все ритмы в том же порядке, что и в легенде.
  ///
  /// Порядок задаём сами по `barIndex`: `touchedSpots` приходит в порядке
  /// касания, и без сортировки строки прыгали бы местами при каждом движении
  /// курсора. Длина ответа должна совпадать с длиной входа, поэтому время
  /// не отдельный пункт, а заголовок первой строки.
  List<LineTooltipItem> _buildTooltipItems(
    List<LineBarSpot> touchedSpots, {
    required TextStyle headerStyle,
    required TextStyle bodyStyle,
  }) {
    final sorted = [...touchedSpots]
      ..sort((a, b) => a.barIndex.compareTo(b.barIndex));

    return [
      for (var i = 0; i < sorted.length; i++)
        () {
          final spot = sorted[i];
          final name =
              spot.barIndex < _bandNames.length
                  ? _bandNames[spot.barIndex]
                  : '—';
          final line = '$name  ${spot.y.toStringAsFixed(3)} отн.';
          final lineStyle = bodyStyle.copyWith(color: spot.bar.color);
          if (i > 0) {
            return LineTooltipItem(line, lineStyle, textAlign: TextAlign.left);
          }
          // Время берём с оси X — она у ритмов в секундах наблюдения.
          return LineTooltipItem(
            formatClock(spot.x.round()),
            headerStyle,
            textAlign: TextAlign.left,
            children: [TextSpan(text: '\n$line', style: lineStyle)],
          );
        }(),
    ];
  }

  LineChartBarData _buildLineBar(List<FlSpot> data, Color color) {
    final validData = data
        .where((spot) => spot.x.isFinite && spot.y.isFinite)
        .toList(growable: false);
    return LineChartBarData(
      spots: validData,
      color: color,
      barWidth: 2,
      isCurved: true,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }
}

class _Legend extends StatelessWidget {
  final List<_LegendItemData> items;

  const _Legend({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children:
          items.map((item) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.color,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  item.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }).toList(),
    );
  }
}

class _LegendItemData {
  final Color color;
  final String label;

  const _LegendItemData(this.color, this.label);
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
