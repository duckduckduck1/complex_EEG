import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class PlotScafold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No data available'));
    final xRange = _calculateXRange(data);

    // Рассчитываем диапазон по Y

    final yRange = _calculateYRange(data);
    final yInterval = _calculateYInterval(yRange.maxY - yRange.minY);
    return LineChart(
      duration: Duration(milliseconds: 4),
      LineChartData(
        minX: data.first.x,
        maxX: data.last.x,
        minY: yRange.minY,
        maxY: yRange.maxY,
        lineTouchData: const LineTouchData(handleBuiltInTouches: false),
        gridData: FlGridData(
          show: true,
          verticalInterval: 1, // Вертикальные линии каждую секунду
          horizontalInterval: 1, // Горизонтальные линии на целых значениях Y
          getDrawingVerticalLine:
              (value) =>
                  FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1),
          getDrawingHorizontalLine:
              (value) =>
                  FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1, // Подписи каждую секунду
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                return value % 1 == 0
                    ? Text(value.toInt().toString())
                    : const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yInterval, // Подписи на целых значениях Y
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                return (value % yInterval == 0 || value == 0)
                    ? Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(value.toStringAsFixed(yInterval < 1 ? 1 : 0)),
                    )
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
        lineBarsData: [
          LineChartBarData(
            spots: data,
            dotData: const FlDotData(show: false),
            color: Colors.blue,
            barWidth: 2,
          ),
        ],
      ),
    );
  }

  ({double minX, double maxX}) _calculateXRange(List<FlSpot> data) {
    if (visibleTimeSeconds != null && data.isNotEmpty) {
      final maxX = data.last.x;
      return (minX: maxX - visibleTimeSeconds!, maxX: maxX);
    }
    return (minX: data.first.x, maxX: data.last.x);
  }

  ({double minY, double maxY}) _calculateYRange(List<FlSpot> data) {
    if (data.isEmpty) return (minY: -1, maxY: 1);

    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final spot in data) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }

    // Добавляем отступ
    final padding = (maxY - minY) * paddingFactor;
    return (minY: minY - padding, maxY: maxY + padding);
  }

  double _calculateYInterval(double yRange) {
    final double absMaxY = yRange / 2; // Максимальное абсолютное значение
    if (absMaxY <= 2) return 0.5;
    if (absMaxY <= 5) return 1;
    if (absMaxY <= 10) return 2;
    if (absMaxY <= 20) return 5;
    return 10;
  }
}
