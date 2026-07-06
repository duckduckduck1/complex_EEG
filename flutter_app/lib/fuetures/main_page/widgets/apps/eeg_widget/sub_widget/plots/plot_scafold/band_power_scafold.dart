import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:iot/theme.dart';

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
  });

  @override
  Widget build(BuildContext context) {
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
    final xInterval = _niceInterval(ensuredMaxX - minX);
    final yInterval = _niceInterval(1);
    final gridColor = palette.grid.withValues(alpha: 0.72);
    final baselineColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.34);
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    return Column(
      children: [
        _Legend(
          items: [
            _LegendItemData(colors.delta, 'Delta'),
            _LegendItemData(colors.theta, 'Theta'),
            _LegendItemData(colors.alpha, 'Alpha'),
            _LegendItemData(colors.beta, 'Beta'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
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
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideVertically: true,
                    fitInsideHorizontally: true,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          spot.y.toStringAsFixed(3),
                          TextStyle(
                            color: spot.bar.color,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
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
                      reservedSize: 30,
                      getTitlesWidget:
                          (value, _) => _AxisLabel(
                            text: '${_formatTick(value, xInterval)} с',
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
                          (value, _) => _AxisLabel(
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
      ],
    );
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
