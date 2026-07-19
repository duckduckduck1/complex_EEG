import 'package:eeg_app_max30003_stm32/core/signal/butterworth_chain.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

class IirStreamingFilterFactory implements StreamingFilterFactory {
  const IirStreamingFilterFactory({this.sampleRateHz = 250});

  final double sampleRateHz;

  @override
  StreamingFilter create(RecordingFilters filters) {
    final chain = ButterworthChain.build(
      sampleRateHz: sampleRateHz,
      lowPassHz: filters.isLpEnabled ? filters.lpHz : null,
      highPassHz: filters.isHpEnabled ? filters.hpHz : null,
      notchHz: filters.isNotchEnabled ? filters.notchHz : null,
    );
    if (chain.isEmpty) {
      return const PassThroughStreamingFilter();
    }
    return IirStreamingFilter(chain);
  }
}

/// Butterworth-фильтр записи, обрабатывающий поток по одному отсчёту.
///
/// Тонкая обёртка над [ButterworthChain]: сам каскад общий с живым графиком,
/// здесь только округление до целых микровольт — в `signal.bin` пишется `int32`.
class IirStreamingFilter implements StreamingFilter {
  IirStreamingFilter(this._chain);

  final ButterworthChain _chain;

  @override
  int filter(int sampleMicrovolts) =>
      _chain.filter(sampleMicrovolts.toDouble()).round();
}
