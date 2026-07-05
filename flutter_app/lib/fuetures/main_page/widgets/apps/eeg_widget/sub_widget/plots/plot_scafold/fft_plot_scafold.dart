import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class FrequencyPlot extends StatefulWidget {
  final List<FlSpot> data;
  final Color lineColor;
  final double? minY;
  final double? maxY;
  final double maxFrequency;
  final double smoothingFactor;
  final double paddingFactor;
  final bool showTooltip;

  const FrequencyPlot({
    super.key,
    required this.data,
    this.lineColor = Colors.green,
    this.minY,
    this.maxY,
    this.maxFrequency = 40,
    this.smoothingFactor = 0.1,
    this.paddingFactor = 0.2,
    this.showTooltip = true,
  });

  @override
  State<FrequencyPlot> createState() => _FrequencyPlotState();
}

class _FrequencyPlotState extends State<FrequencyPlot> {
  double _currentMinY = -60;
  double _currentMaxY = 0;
  double _targetMinY = -60;
  double _targetMaxY = 0;
  double _lastRange = 60;

  @override
  Widget build(BuildContext context) {
    final validData =
        widget.data
            .where(
              (spot) =>
                  spot.y.isFinite &&
                  spot.x >= 0 &&
                  spot.x <= widget.maxFrequency,
            )
            .toList();

    if (validData.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }

    _calculateNewRange(validData);
    _currentMinY = _smoothValue(_currentMinY, _targetMinY);
    _currentMaxY = _smoothValue(_currentMaxY, _targetMaxY);
    _lastRange = _currentMaxY - _currentMinY;

    // Гарантируем минимальный видимый диапазон
    final ensuredMinY = min(_currentMinY, -10);
    final ensuredMaxY = max(_currentMaxY, 10);
    final ensuredRange = ensuredMaxY - ensuredMinY;

    final yInterval = _calculateYInterval(ensuredRange.toDouble());
    final xInterval = _calculateXInterval(widget.maxFrequency);

    return ClipRect(
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: widget.maxFrequency,
          minY: ensuredMinY.toDouble(),
          maxY: ensuredMaxY.toDouble(),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              curveSmoothness: 0.15,
              spots: validData,
              dotData: const FlDotData(show: false),
              color: widget.lineColor,
              barWidth: 2,
              shadow: Shadow(
                color: widget.lineColor.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(2, 2),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.lineColor.withValues(alpha: 0.25),
                    widget.lineColor.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: widget.showTooltip,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.x.toStringAsFixed(1)} Hz\n${spot.y.toStringAsFixed(1)} dB',
                    const TextStyle(color: Colors.white, fontSize: 12),
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
                (value) => FlLine(
                  color: Colors.grey.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
            getDrawingHorizontalLine:
                (value) => FlLine(
                  color: Colors.grey.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: xInterval,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  return value % xInterval == 0
                      ? _buildAxisText('${value.toInt()}Hz')
                      : const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: yInterval,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  return (value % yInterval == 0 || value == 0)
                      ? _buildAxisText('${value.toInt()}')
                      : const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAxisText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: Colors.grey.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  void _calculateNewRange(List<FlSpot> validData) {
    if (validData.isEmpty) return;

    final sortedY = validData.map((e) => e.y).toList()..sort();
    final minIndex = (sortedY.length * 0.05).floor();
    final maxIndex = (sortedY.length * 0.95).ceil();

    final stableMinY = sortedY[minIndex.clamp(0, sortedY.length - 1)];
    final stableMaxY = sortedY[maxIndex.clamp(0, sortedY.length - 1)];

    final minRange = 20.0;
    final effectiveRange = max(stableMaxY - stableMinY, minRange);

    _targetMinY =
        widget.minY ?? (stableMinY - effectiveRange * widget.paddingFactor);
    _targetMaxY =
        widget.maxY ?? (stableMaxY + effectiveRange * widget.paddingFactor);

    final maxChange = _lastRange * 0.5;
    _targetMinY = _targetMinY.clamp(
      _currentMinY - maxChange,
      _currentMinY + maxChange,
    );
    _targetMaxY = _targetMaxY.clamp(
      _currentMaxY - maxChange,
      _currentMaxY + maxChange,
    );
  }

  double _smoothValue(double current, double target) {
    return current + (target - current) * widget.smoothingFactor;
  }

  double _calculateYInterval(double range) {
    if (range <= 20) return 5;
    if (range <= 40) return 10;
    if (range <= 80) return 20;
    return 50;
  }

  double _calculateXInterval(double maxFreq) {
    if (maxFreq <= 10) return 2;
    if (maxFreq <= 20) return 5;
    if (maxFreq <= 50) return 10;
    return 20;
  }
}
