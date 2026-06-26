import 'dart:math';

import 'package:flutter_app/core/ids/ulid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UlidGenerator', () {
    test('возвращает 26 символов из алфавита Crockford Base32', () {
      final ulid = UlidGenerator().generate();
      expect(ulid.length, 26);
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(ulid), isTrue);
    });

    test('строка exp_<ULID> укладывается в серверный regex', () {
      final id = 'exp_${UlidGenerator().generate()}';
      expect(RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id), isTrue);
    });

    test(
      'время кодируется в первых 10 символах и растёт лексикографически',
      () {
        var ms = 1000;
        final generator = UlidGenerator(
          now: () => DateTime.fromMillisecondsSinceEpoch(ms),
          random: Random(1),
        );
        final earlier = generator.generate();
        ms = 2000;
        final later = generator.generate();
        expect(
          earlier.substring(0, 10).compareTo(later.substring(0, 10)) < 0,
          isTrue,
        );
      },
    );

    test('при одинаковом времени случайная часть различается', () {
      final generator = UlidGenerator(
        now: () => DateTime.fromMillisecondsSinceEpoch(42),
        random: Random(7),
      );
      final first = generator.generate();
      final second = generator.generate();
      expect(first.substring(0, 10), second.substring(0, 10));
      expect(first, isNot(equals(second)));
    });
  });
}
