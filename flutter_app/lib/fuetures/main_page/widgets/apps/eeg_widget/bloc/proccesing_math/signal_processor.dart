import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:iirjdart/butterworth.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

class SignalProcessor {
  final int bufferSize;
  final double sampleRate;
  late final FFT _fft;
  late final List<double> _hannWindow;
  FillterSettings settings;
  late final Butterworth butterworth;
  static const Map<String, List<double>> frequencyBands = {
    'Delta': [0.5, 4.0],
    'Theta': [4.0, 8.0],
    'Alpha': [8.0, 13.0],
    'Beta': [13.0, 35.0],
  };

  SignalProcessor(this.bufferSize, this.sampleRate, this.settings) {
    if (bufferSize <= 0 || !_isPowerOfTwo(bufferSize)) {
      throw ArgumentError('Buffer size must be a positive power of two');
    }
    _fft = FFT(bufferSize);
    _hannWindow = _createHannWindow(bufferSize);
    butterworth = Butterworth();
  }

  bool _isPowerOfTwo(int n) => (n & (n - 1)) == 0 && n != 0;

  List<FlSpot> computeFrequencySpectrum(List<double> timeDomainData) {
    if (timeDomainData.length != bufferSize) {
      throw ArgumentError('Input data length must match buffer size');
    }

    final windowed = _applyWindow(timeDomainData, _hannWindow);
    final spectrum = _fft.realFft(Float64List.fromList(windowed));
    return _computeAmplitudeSpectrum(spectrum);
  }

  List<double> _createHannWindow(int size) {
    return List.generate(size, (i) => 0.5 * (1 - cos(2 * pi * i / (size - 1))));
  }

  List<double> _applyWindow(List<double> data, List<double> window) {
    return List.generate(data.length, (i) => data[i] * window[i]);
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

  List<double> _filter(List<double> raw, int filtType) {
    //int filtType - тип фильтрации 0 - lp, 1 - hp , 2 - notch
    List<double> filteredData = [];
    switch (filtType) {
      case 0:
        butterworth.lowPass(1, sampleRate, settings.lp);
        for (var v in raw) {
          filteredData.add(butterworth.filter(v));
        }
        break;
      case 1:
        butterworth.highPass(2, sampleRate, settings.hp);
        for (var v in raw) {
          filteredData.add(butterworth.filter(v));
        }
        break;
      case 2:
        butterworth.bandStop(3, sampleRate, settings.notch, 10);
        for (var v in raw) {
          filteredData.add(butterworth.filter(v));
        }
        break;
      default:
        break;
    }

    return filteredData;
  }

  List<double> filterSignal(List<double> rawData) {
    List<double> f = [];
    if (settings.isLpOn) {
      f = _filter(rawData, 0);
    }
    if (settings.isHpOn) {
      if (f.isEmpty) {
        f = _filter(rawData, 1);
      } else {
        f = _filter(f, 1);
      }
    }

    if (settings.isNotchOn) {
      if (f.isEmpty) {
        f = _filter(rawData, 2);
      } else {
        f = _filter(f, 2);
      }
    }
    if (f.isEmpty) {
      return rawData;
    }
    return f;
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
