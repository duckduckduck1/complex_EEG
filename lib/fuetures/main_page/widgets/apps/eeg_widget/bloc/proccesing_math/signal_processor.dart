import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';
import 'package:fl_chart/fl_chart.dart';

class SignalProcessor {
  final int bufferSize;
  final double sampleRate;
  late final FFT _fft;
  late final Float64List _hannWindow;

  /// Переиспользуемый вход FFT: 1024 значения, которые перезаписываются на
  /// каждом расчёте. Заводить их заново незачем — размер не меняется.
  late final Float64List _windowed;

  static const Map<String, List<double>> frequencyBands = {
    'Delta': [0.5, 4.0],
    'Theta': [4.0, 8.0],
    'Alpha': [8.0, 13.0],
    'Beta': [13.0, 35.0],
  };

  SignalProcessor(this.bufferSize, this.sampleRate) {
    if (bufferSize <= 0 || !_isPowerOfTwo(bufferSize)) {
      throw ArgumentError('Buffer size must be a positive power of two');
    }
    _fft = FFT(bufferSize);
    _hannWindow = _createHannWindow(bufferSize);
    _windowed = Float64List(bufferSize);
  }

  bool _isPowerOfTwo(int n) => (n & (n - 1)) == 0 && n != 0;

  /// Спектр окна отсчётов.
  ///
  /// Принимает [Iterable], а не [List], чтобы кольцевой буфер графика не надо
  /// было раскладывать в отдельный список ради вызова. Оконная функция
  /// применяется прямо в переиспользуемый [_windowed] — раньше здесь на каждый
  /// вызов создавались два новых списка по 1024 значения.
  List<FlSpot> computeFrequencySpectrum(Iterable<double> timeDomainData) {
    if (timeDomainData.length != bufferSize) {
      throw ArgumentError('Input data length must match buffer size');
    }

    var i = 0;
    for (final value in timeDomainData) {
      _windowed[i] = value * _hannWindow[i];
      i++;
    }
    final spectrum = _fft.realFft(_windowed);
    return _computeAmplitudeSpectrum(spectrum);
  }

  Float64List _createHannWindow(int size) {
    return Float64List.fromList(
      List<double>.generate(
        size,
        (i) => 0.5 * (1 - cos(2 * pi * i / (size - 1))),
      ),
    );
  }

  List<FlSpot> _computeAmplitudeSpectrum(Float64x2List spectrum) {
    final points = <FlSpot>[];
    final halfLength = spectrum.length ~/ 2;

    for (int k = 0; k < halfLength; k++) {
      final freq = k * sampleRate / bufferSize;
      if (freq > sampleRate / 2) break;

      final real = spectrum[k].x;
      final imag = spectrum[k].y;
      final magnitude = sqrt(real * real + imag * imag) / bufferSize;
      final db = 20 * log(magnitude) / ln10;
      points.add(FlSpot(freq, db.isFinite ? db : -120));
    }
    return points;
  }

  Map<String, double> computeBandPowers(List<FlSpot> spectrum) {
    final bandPowers = <String, double>{};
    double totalPower = 0.0;

    // 1. Вычисляем "сырые" мощности и общую мощность (0.5–35 Гц)
    frequencyBands.forEach((band, range) {
      double power = 0.0;
      for (final spot in spectrum) {
        if (spot.x >= range[0] && spot.x <= range[1]) {
          power += pow(10, spot.y / 10); // Из dB в линейную шкалу
        }
      }
      bandPowers[band] = power;
      totalPower += power; // Суммируем для P~Σ~
    });

    // 2. Нормируем каждую полосу на P~Σ~
    if (totalPower > 0) {
      bandPowers.updateAll((band, power) => power / totalPower);
    }

    return bandPowers;
  }
}
