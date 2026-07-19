import 'package:iirjdart/butterworth.dart';

/// Каскад Butterworth-фильтров, обрабатывающий поток по одному отсчёту.
///
/// Один экземпляр на каскад и **одно проектирование коэффициентов на всю
/// жизнь**. IIR-фильтр по определению имеет состояние: следующий отсчёт
/// считается по предыдущим. Поэтому его нельзя ни перепроектировать на ходу, ни
/// прогонять заново по всему буферу — и то и другое перезапускает переходный
/// процесс и даёт на выходе не тот сигнал.
///
/// Ровно так и было в графике: старый `SignalProcessor.filterSignal` на каждый отсчёт
/// пересчитывал коэффициенты и заново фильтровал все 1024 значения одним общим
/// экземпляром `Butterworth`, из-за чего состояние ФНЧ протекало в ФВЧ. Картинка
/// на экране расходилась с тем, что писалось в файл, где каскад всегда был
/// потоковым.
///
/// Живёт в `core`, потому что нужен обоим: и записи, и живому графику. Класть
/// его в один из слоёв значило бы тянуть в другой чужую зависимость.
class ButterworthChain {
  ButterworthChain(this._stages);

  /// Пустой каскад: отсчёты проходят как есть.
  ButterworthChain.passThrough() : _stages = const [];

  /// Собирает каскад в порядке ФНЧ → ФВЧ → режекторный.
  ///
  /// Порядки фильтров (1, 2, 3) и ширина режекции (10 Гц) — те же, что были в
  /// записи; менять их здесь значит менять то, что уходит в `signal.bin`.
  factory ButterworthChain.build({
    required double sampleRateHz,
    double? lowPassHz,
    double? highPassHz,
    double? notchHz,
  }) {
    final stages = <Butterworth>[
      if (lowPassHz != null) Butterworth()..lowPass(1, sampleRateHz, lowPassHz),
      if (highPassHz != null)
        Butterworth()..highPass(2, sampleRateHz, highPassHz),
      if (notchHz != null)
        Butterworth()..bandStop(3, sampleRateHz, notchHz, 10),
    ];
    return ButterworthChain(stages);
  }

  final List<Butterworth> _stages;

  bool get isEmpty => _stages.isEmpty;

  /// Пропускает один отсчёт через весь каскад.
  double filter(double sample) {
    var value = sample;
    for (final stage in _stages) {
      value = stage.filter(value);
    }
    return value;
  }
}
