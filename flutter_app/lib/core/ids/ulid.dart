import 'dart:math';

/// Генератор ULID (Universally Unique Lexicographically Sortable Identifier).
///
/// 128 бит: 48 бит — время в миллисекундах, 80 бит — случайность. Кодируется в
/// 26 символов Crockford Base32 (только `0-9A-Z` без I, L, O, U), поэтому строка
/// `exp_<ULID>` укладывается в серверный regex `^[a-zA-Z0-9_-]{1,64}$`
/// (см. docs/flutter_app/architecture.md).
///
/// [now] и [random] инъектируются для детерминированных тестов
/// (см. docs/flutter_app/testing.md — `FakeClock`).
class UlidGenerator {
  UlidGenerator({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  final DateTime Function() _now;
  final Random _random;

  /// Алфавит Crockford Base32.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Время: 48 бит → 10 символов по 5 бит.
  static const int _timeLength = 10;

  /// Случайность: 80 бит → 16 символов по 5 бит.
  static const int _randomLength = 16;

  /// Сгенерировать новый ULID длиной 26 символов.
  String generate() {
    final timeChars = List<String>.filled(_timeLength, _alphabet[0]);
    var time = _now().millisecondsSinceEpoch;
    for (var i = _timeLength - 1; i >= 0; i--) {
      timeChars[i] = _alphabet[time & 0x1f];
      time = time >> 5;
    }

    final buffer = StringBuffer()..writeAll(timeChars);
    for (var i = 0; i < _randomLength; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }
}
