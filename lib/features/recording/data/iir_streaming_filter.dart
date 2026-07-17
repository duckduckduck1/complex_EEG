import 'package:iirjdart/butterworth.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

class IirStreamingFilterFactory implements StreamingFilterFactory {
  const IirStreamingFilterFactory({this.sampleRateHz = 250});

  final double sampleRateHz;

  @override
  StreamingFilter create(RecordingFilters filters) {
    final chain = <Butterworth>[];

    if (filters.isLpEnabled) {
      chain.add(Butterworth()..lowPass(1, sampleRateHz, filters.lpHz));
    }
    if (filters.isHpEnabled) {
      chain.add(Butterworth()..highPass(2, sampleRateHz, filters.hpHz));
    }
    if (filters.isNotchEnabled) {
      chain.add(Butterworth()..bandStop(3, sampleRateHz, filters.notchHz, 10));
    }

    if (chain.isEmpty) {
      return const PassThroughStreamingFilter();
    }
    return IirStreamingFilter(chain);
  }
}

/// Butterworth-фильтр записи, обрабатывающий поток по одному отсчёту.
///
/// Держит состояние между вызовами, поэтому годится для живой записи: цепочка
/// проектируется один раз при старте, дальше каждый отсчёт просто проходит
/// сквозь неё. Не путать с `SignalProcessor.filterSignal`, который
/// перефильтровывает весь буфер целиком — тот только для графика.
class IirStreamingFilter implements StreamingFilter {
  IirStreamingFilter(this._chain);

  final List<Butterworth> _chain;

  @override
  int filter(int sampleMicrovolts) {
    var value = sampleMicrovolts.toDouble();
    for (final filter in _chain) {
      value = filter.filter(value);
    }
    return value.round();
  }
}
