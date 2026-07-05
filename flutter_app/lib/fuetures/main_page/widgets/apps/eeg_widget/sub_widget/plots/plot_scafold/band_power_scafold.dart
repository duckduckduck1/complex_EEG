import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class BandPowerPlot extends StatelessWidget {
  final List<FlSpot> deltaData;
  final List<FlSpot> thetaData;
  final List<FlSpot> alphaData;
  final List<FlSpot> betaData;
  final double maxFrequency;
  final Color deltaColor;
  final Color thetaColor;
  final Color alphaColor;
  final Color betaColor;

  const BandPowerPlot({
    super.key,
    required this.deltaData,
    required this.thetaData,
    required this.alphaData,
    required this.betaData,
    this.maxFrequency = 60,
    this.deltaColor = Colors.blue,
    this.thetaColor = Colors.green,
    this.alphaColor = Colors.orange,
    this.betaColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Легенда
        _buildLegend(),
        const SizedBox(height: 8),
        // График
        Expanded(
          child: LineChart(
            curve: Curves.linear,
            duration: Duration(microseconds: 300),
            LineChartData(
              minX: deltaData.isNotEmpty ? deltaData.first.x : 0,
              maxX: deltaData.isNotEmpty ? deltaData.last.x : maxFrequency,
              minY: 0,
              maxY: 1.0,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
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
                _buildLineBar(deltaData, deltaColor),
                _buildLineBar(thetaData, thetaColor),
                _buildLineBar(alphaData, alphaColor),
                _buildLineBar(betaData, betaColor),
              ],
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 10,
                    getTitlesWidget: (value, _) => Text('${value.toInt()}s'),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 0.2,
                    getTitlesWidget:
                        (value, _) => Text(value.toStringAsFixed(1)),
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
                verticalInterval: 10,
                horizontalInterval: 0.2,
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
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Легенда графика
  Widget _buildLegend() {
    // TODO: Переделать из метода в виджет, для оптимизации
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(deltaColor, 'Delta'),
        const SizedBox(width: 16),
        _buildLegendItem(thetaColor, 'Theta'),
        const SizedBox(width: 16),
        _buildLegendItem(alphaColor, 'Alpha'),
        const SizedBox(width: 16),
        _buildLegendItem(betaColor, 'Beta'),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  LineChartBarData _buildLineBar(List<FlSpot> data, Color color) {
    return LineChartBarData(
      spots: data,
      color: color,
      barWidth: 2,
      isCurved: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
      shadow: Shadow(color: color.withValues(alpha: 0.2)),
    );
  }
}
