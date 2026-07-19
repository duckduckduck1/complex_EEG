import 'package:fl_chart/fl_chart.dart';

/// Прореживание точек графика под ширину, в которую его рисуют.
///
/// В панель мозаики шириной 380 px невозможно нарисовать 1024 точки — их
/// физически некуда класть, а стоят они полной цены при отрисовке. Берём по две
/// точки на пиксельную колонку: минимум и максимум внутри неё.
///
/// Именно min/max, а не «каждая N-я»: прореживание по шагу съедает одиночные
/// выбросы, а на ЭЭГ артефакт длиной в пару отсчётов — это ровно то, ради чего
/// оператор в график и смотрит. Огибающая при min/max сохраняется полностью,
/// теряется только форма внутри колонки, которой на экране всё равно нет.
///
/// Данные при этом не трогаются: прореживание живёт на стороне отрисовки,
/// буферы [RtEegDataBloc] остаются полными.
List<FlSpot> decimateMinMax(List<FlSpot> spots, int targetColumns) {
  if (targetColumns <= 0) return const <FlSpot>[];
  // Меньше двух точек на колонку прореживать нечего — вернём как есть.
  if (spots.length <= targetColumns * 2) return spots;

  final result = <FlSpot>[];
  final bucketSize = spots.length / targetColumns;

  for (var column = 0; column < targetColumns; column++) {
    final start = (column * bucketSize).floor();
    final end = ((column + 1) * bucketSize).floor().clamp(
      start + 1,
      spots.length,
    );

    var minSpot = spots[start];
    var maxSpot = spots[start];
    for (var i = start + 1; i < end; i++) {
      final spot = spots[i];
      if (spot.y < minSpot.y) minSpot = spot;
      if (spot.y > maxSpot.y) maxSpot = spot;
    }

    // Порядок по x: линия не должна ходить назад по времени.
    if (minSpot.x <= maxSpot.x) {
      result.add(minSpot);
      if (maxSpot != minSpot) result.add(maxSpot);
    } else {
      result.add(maxSpot);
      result.add(minSpot);
    }
  }

  return result;
}
