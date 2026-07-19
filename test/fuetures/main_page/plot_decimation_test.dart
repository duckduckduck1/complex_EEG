import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_decimation.dart';

void main() {
  test('короткий ряд возвращается как есть', () {
    final spots = List<FlSpot>.generate(10, (i) => FlSpot(i.toDouble(), 1));
    expect(decimateMinMax(spots, 100), same(spots));
  });

  test('прореженный ряд укладывается в две точки на колонку', () {
    final spots = List<FlSpot>.generate(1024, (i) => FlSpot(i.toDouble(), 0));
    final result = decimateMinMax(spots, 100);
    expect(result.length, lessThanOrEqualTo(200));
    expect(result, isNotEmpty);
  });

  test('одиночный выброс переживает прореживание', () {
    // Ровно то, ради чего min/max: артефакт длиной в один отсчёт среди тысячи.
    // Прореживание «каждая N-я» его бы потеряло.
    final spots = List<FlSpot>.generate(
      1000,
      (i) => FlSpot(i.toDouble(), i == 517 ? 900.0 : 0.0),
    );

    final result = decimateMinMax(spots, 50);

    expect(
      result.any((spot) => spot.y == 900.0 && spot.x == 517.0),
      isTrue,
      reason: 'пик обязан остаться на месте',
    );
  });

  test('минимум и максимум сохраняются оба', () {
    final spots = List<FlSpot>.generate(
      1000,
      (i) => FlSpot(i.toDouble(), i == 100 ? -50.0 : (i == 900 ? 70.0 : 0.0)),
    );

    final result = decimateMinMax(spots, 40);
    final ys = result.map((spot) => spot.y);

    expect(ys, contains(-50.0));
    expect(ys, contains(70.0));
  });

  test('точки идут по возрастанию x', () {
    final spots = List<FlSpot>.generate(
      600,
      (i) => FlSpot(i.toDouble(), (i % 7) - 3.0),
    );

    final result = decimateMinMax(spots, 30);

    for (var i = 1; i < result.length; i++) {
      expect(
        result[i].x,
        greaterThanOrEqualTo(result[i - 1].x),
        reason: 'линия не должна ходить назад по времени',
      );
    }
  });

  test('нулевая ширина не роняет прореживание', () {
    final spots = List<FlSpot>.generate(100, (i) => FlSpot(i.toDouble(), 1));
    expect(decimateMinMax(spots, 0), isEmpty);
  });
}
