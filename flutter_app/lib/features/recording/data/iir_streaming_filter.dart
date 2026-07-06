import 'package:iirjdart/butterworth.dart';
import 'package:iot/features/recording/domain/recording_models.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

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
