// Форматирование времени наблюдения в ЧЧ:ММ:СС.
//
// Часы появляются только когда накопились, иначе ММ:СС — оператор мыслит
// временем, а при долгой записи (часы, сутки) секунды не превращаются в
// огромное число.

const _defaultSampleRateHz = 250;

/// Секунды → `ММ:СС` или `Ч:ММ:СС`, если набрался хотя бы час.
String formatClock(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  final mmss =
      '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  return hours > 0 ? '$hours:$mmss' : mmss;
}

/// Отсчёты → время наблюдения по частоте дискретизации.
String formatClockFromSamples(
  int sampleCount, {
  int sampleRateHz = _defaultSampleRateHz,
}) {
  final safe = sampleCount < 0 ? 0 : sampleCount;
  return formatClock(safe ~/ sampleRateHz);
}

/// Разбирает ввод времени в секунды. Принимает `сс`, `мм:сс` или `чч:мм:сс`.
/// Возвращает `null`, если строка не разобралась.
int? parseClockToSeconds(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final parts = trimmed.split(':');
  if (parts.length > 3) {
    return null;
  }
  var total = 0;
  for (final part in parts) {
    final value = int.tryParse(part.trim());
    if (value == null || value < 0) {
      return null;
    }
    total = total * 60 + value;
  }
  return total;
}

/// Отсчёты → секунды по частоте дискретизации.
int samplesToSeconds(
  int sampleCount, {
  int sampleRateHz = _defaultSampleRateHz,
}) {
  final safe = sampleCount < 0 ? 0 : sampleCount;
  return safe ~/ sampleRateHz;
}

/// Секунды → индекс отсчёта по частоте дискретизации.
int secondsToSamples(int seconds, {int sampleRateHz = _defaultSampleRateHz}) {
  final safe = seconds < 0 ? 0 : seconds;
  return safe * sampleRateHz;
}
