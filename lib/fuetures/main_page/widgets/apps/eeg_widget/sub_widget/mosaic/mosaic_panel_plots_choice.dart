import 'package:flutter/foundation.dart';

/// Какие графики показывает панель мозаики.
///
/// Выбор у каждой панели свой: у одной мыши смотрят сигнал, у соседней — ритмы,
/// и навязывать им общий состав значит заставлять оператора листать вкладки
/// ровно за тем, ради чего мозаика и делалась.
///
/// Инвариант: **хотя бы один график всегда включён**. Пустая панель не несёт
/// ничего, кроме заголовка, но продолжает занимать место в сетке — поэтому
/// последний включённый график выключить нельзя, и кнопка это показывает.
@immutable
class MosaicPlotsChoice {
  const MosaicPlotsChoice({
    this.signal = true,
    this.bands = true,
    this.spectrum = false,
  }) : assert(signal || bands || spectrum, 'панель без графиков бессмысленна');

  final bool signal;
  final bool bands;
  final bool spectrum;

  int get enabledCount =>
      (signal ? 1 : 0) + (bands ? 1 : 0) + (spectrum ? 1 : 0);

  /// Можно ли выключить конкретный график: последний включённый — нельзя.
  bool canToggleOff(MosaicPlotKind kind) => !(isOn(kind) && enabledCount == 1);

  bool isOn(MosaicPlotKind kind) => switch (kind) {
    MosaicPlotKind.signal => signal,
    MosaicPlotKind.bands => bands,
    MosaicPlotKind.spectrum => spectrum,
  };

  /// Переключает график. Попытка погасить последний включённый ничего не
  /// меняет — молча, потому что кнопка в этот момент и так показана неактивной.
  MosaicPlotsChoice toggle(MosaicPlotKind kind) {
    if (!canToggleOff(kind)) return this;
    return switch (kind) {
      MosaicPlotKind.signal => MosaicPlotsChoice(
        signal: !signal,
        bands: bands,
        spectrum: spectrum,
      ),
      MosaicPlotKind.bands => MosaicPlotsChoice(
        signal: signal,
        bands: !bands,
        spectrum: spectrum,
      ),
      MosaicPlotKind.spectrum => MosaicPlotsChoice(
        signal: signal,
        bands: bands,
        spectrum: !spectrum,
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MosaicPlotsChoice &&
      other.signal == signal &&
      other.bands == bands &&
      other.spectrum == spectrum;

  @override
  int get hashCode => Object.hash(signal, bands, spectrum);
}

enum MosaicPlotKind {
  signal('Сигнал'),
  bands('Ритмы'),
  spectrum('Спектр');

  const MosaicPlotKind(this.displayName);

  final String displayName;
}
