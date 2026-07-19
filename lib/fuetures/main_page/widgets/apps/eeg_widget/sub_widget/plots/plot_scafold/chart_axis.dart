import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Оси живых графиков: размер подписей, место под них и сами подписи.
///
/// Здесь нет ни одного подобранного на глаз пикселя, и это главное. Раньше
/// размеры шрифта и `reservedSize` стояли константами (10/13, 22/30/40/42),
/// которые я угадывал под один размер окна: на панели мозаики подписи налезали
/// на график, а крайние уезжали за рамку. Теперь и то и другое **считается** —
/// шрифт от размера графика, ширина полосы под подписи от их измеренной ширины.
///
/// Три графика (сигнал, спектр, ритмы) раньше держали по своей копии виджета
/// подписи. Копии разъезжались: правку приходилось делать трижды, и один раз я
/// это и забыл. Теперь подпись одна на всех.
class ChartAxis {
  ChartAxis._(this.labelStyle, this._textScaler, this._chartSize);

  /// Считает стиль подписей под размер, в который график реально рисуют.
  ///
  /// Размер шрифта берётся от меньшей стороны графика: панель мозаики и вкладка
  /// отличаются в разы, и одна константа не годится обеим. Границы 9..13 —
  /// чтобы подпись не стала нечитаемой на крошечной панели и не разъехалась на
  /// большом мониторе. Системный масштаб текста учитывается отдельно, через
  /// [TextScaler]: пользовательскую настройку «крупный шрифт» жёсткий
  /// `fontSize` просто игнорировал.
  factory ChartAxis.of(BuildContext context, Size chartSize) {
    final theme = Theme.of(context);
    final shortestSide = min(chartSize.width, chartSize.height);
    final fontSize = (shortestSide / 22).clamp(9.0, 13.0);
    final style =
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(fontSize: fontSize);
    return ChartAxis._(style, MediaQuery.textScalerOf(context), chartSize);
  }

  final TextStyle labelStyle;
  final TextScaler _textScaler;
  final Size _chartSize;

  /// Отступ между подписью и полем графика.
  static const double space = 4;

  /// Меряет строку в стиле подписей (или в [style], если он задан).
  ///
  /// Мерить, а не прикидывать: ширина зависит от шрифта, начертания и
  /// системного масштаба, и любое угаданное число рано или поздно окажется мало.
  Size measure(String text, {TextStyle? style}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style ?? labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: _textScaler,
      maxLines: 1,
    )..layout();
    return painter.size;
  }

  double _widest(Iterable<String> labels) {
    var widest = 0.0;
    for (final label in labels) {
      widest = max(widest, measure(label).width);
    }
    return widest;
  }

  /// Ширина полосы под подписи слева — по самой широкой из [sampleLabels].
  ///
  /// Хватает передать крайние значения оси: они и есть самые длинные, потому
  /// что у них больше всего знаков и у минимума ещё минус.
  double reservedLeft(Iterable<String> sampleLabels) =>
      _widest(sampleLabels) + space + 2;

  /// Высота полосы под подписи снизу.
  double reservedBottom(String sampleLabel) =>
      measure(sampleLabel).height + space + 2;

  /// Сколько засечек поставить, чтобы подписи не слиплись.
  ///
  /// Считается от места: сколько подписей шириной [sampleLabel] влезает на ось
  /// с полуторным зазором. Раньше здесь стояло «3 в мозаике, 5 во вкладке» —
  /// на узкой панели три подписи всё равно налезали друг на друга.
  int ticksAlong(Axis axis, String sampleLabel) {
    final available =
        axis == Axis.horizontal ? _chartSize.width : _chartSize.height;
    final labelSize = measure(sampleLabel);
    final step =
        (axis == Axis.horizontal ? labelSize.width : labelSize.height) * 1.8;
    if (step <= 0) return 2;
    return (available / step).floor().clamp(2, 6);
  }
}

/// Подпись оси.
///
/// Штатный [SideTitleWidget] вместо самодельного `Padding`: он сам знает про
/// сторону оси, отступ и — главное — про [SideTitleFitInsideData], которая
/// заталкивает крайние подписи обратно внутрь области оси. Именно её отсутствие
/// уводило последнюю подпись времени за правый край.
Widget chartAxisLabel({
  required TitleMeta meta,
  required String text,
  required TextStyle? style,
}) {
  return SideTitleWidget(
    meta: meta,
    space: ChartAxis.space,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
    child: Text(text, style: style, maxLines: 1, softWrap: false),
  );
}
