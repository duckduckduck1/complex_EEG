import 'dart:math';

import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

class UlidExperimentIdGenerator implements ExperimentIdGenerator {
  UlidExperimentIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final Random _random;

  /// Машинный идентификатор записи (ULID): время + случайная часть, поэтому
  /// сортируется по возрастанию и уникален без согласования.
  ///
  /// Без префикса: раньше `exp_` был нужен как имя папки, теперь папка зовётся
  /// названием эксперимента, а идентификатор живёт только в `experiment.json`
  /// и в журнале — он привязывает строки журнала к записи и переживает
  /// переименование папки.
  @override
  String nextId() {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return '${_encodeTime(timestamp)}${_encodeRandomness()}';
  }

  String _encodeTime(int timestampMillis) {
    var value = timestampMillis;
    final chars = List<String>.filled(10, '0');
    for (var index = 9; index >= 0; index--) {
      chars[index] = _alphabet[value & 0x1f];
      value ~/= 32;
    }
    return chars.join();
  }

  String _encodeRandomness() {
    final chars = List<String>.filled(16, '0');
    for (var index = 0; index < chars.length; index++) {
      chars[index] = _alphabet[_random.nextInt(32)];
    }
    return chars.join();
  }
}
