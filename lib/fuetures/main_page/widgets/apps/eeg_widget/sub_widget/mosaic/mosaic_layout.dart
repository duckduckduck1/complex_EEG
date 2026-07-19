import 'dart:math';

/// Насколько сильно дыра в последнем ряду перевешивает удачные пропорции.
/// Подобрано так, чтобы 4 устройства давали 2×2, а не 3+1.
const _emptyCellPenalty = 0.5;

/// Раскладка мозаики: сколько колонок взять под [deviceCount] панелей.
///
/// Считаем от **минимального читаемого размера панели**, а не от числа
/// устройств. Иначе десять мышей на ноутбуке превратились бы в десять
/// нечитаемых марок — а мозаика нужна ровно затем, чтобы увидеть, что
/// происходит, и это единственное, чего она не имеет права потерять.
///
/// Если панели нужного размера на экран не помещаются, берём столько колонок,
/// сколько влезает по ширине, и отдаём остальное вертикальной прокрутке. Пусть
/// лучше часть панелей окажется ниже сгиба, чем все станут нечитаемыми.
///
/// Среди раскладок, которые помещаются целиком, выбираем ту, где панель ближе
/// всего к [targetAspectRatio]: график сигнала — линия во времени, ему нужна
/// ширина, но вытянутая в нитку панель тоже не читается. За пустые ячейки в
/// последнем ряду штрафуем: 4 устройства в три колонки дают дыру на пол-ряда,
/// и сетка 2×2 выглядит куда осмысленнее, даже если пропорции чуть хуже.
int mosaicColumns({
  required int deviceCount,
  required double availableWidth,
  required double availableHeight,
  required double gap,
  double minPanelWidth = 260,
  double minPanelHeight = 200,
  double targetAspectRatio = 1.6,
}) {
  if (deviceCount <= 1) return 1;

  double panelWidth(int columns) =>
      (availableWidth - gap * (columns - 1)) / columns;

  double panelHeight(int rows) => (availableHeight - gap * (rows - 1)) / rows;

  // Сколько колонок вообще влезает по ширине.
  var maxColumns = 1;
  for (var columns = 1; columns <= deviceCount; columns++) {
    if (panelWidth(columns) >= minPanelWidth) maxColumns = columns;
  }

  int? bestColumns;
  var bestScore = double.infinity;
  for (var columns = 1; columns <= maxColumns; columns++) {
    final rows = (deviceCount / columns).ceil();
    final height = panelHeight(rows);
    if (height < minPanelHeight) continue;

    final ratio = panelWidth(columns) / height;
    final emptyCells = columns * rows - deviceCount;
    final score =
        (log(ratio) - log(targetAspectRatio)).abs() +
        _emptyCellPenalty * emptyCells / (columns * rows);
    if (score < bestScore) {
      bestScore = score;
      bestColumns = columns;
    }
  }

  // Целиком не помещается — уходим в прокрутку максимально широкой раскладкой.
  return bestColumns ?? maxColumns;
}
