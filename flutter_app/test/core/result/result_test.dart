import 'package:flutter_app/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('Ok несёт значение', () {
      const result = Ok<int, String>(5);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 5);
      expect(result.failureOrNull, isNull);
    });

    test('Err несёт ошибку', () {
      const result = Err<int, String>('boom');
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, 'boom');
    });

    test('map преобразует только Ok', () {
      const ok = Ok<int, String>(2);
      const err = Err<int, String>('e');
      expect(ok.map((v) => v * 10).valueOrNull, 20);
      expect(err.map((v) => v * 10).failureOrNull, 'e');
    });

    test('fold сворачивает оба варианта', () {
      const ok = Ok<int, String>(2);
      const err = Err<int, String>('e');
      expect(ok.fold((v) => 'ok:$v', (f) => 'err:$f'), 'ok:2');
      expect(err.fold((v) => 'ok:$v', (f) => 'err:$f'), 'err:e');
    });

    test('getOrElse возвращает fallback при ошибке', () {
      const ok = Ok<int, String>(7);
      const err = Err<int, String>('e');
      expect(ok.getOrElse((_) => -1), 7);
      expect(err.getOrElse((_) => -1), -1);
    });

    test('равенство по содержимому', () {
      expect(const Ok<int, String>(1), equals(const Ok<int, String>(1)));
      expect(const Err<int, String>('a'), equals(const Err<int, String>('a')));
      expect(const Ok<int, String>(1), isNot(equals(const Ok<int, String>(2))));
    });
  });
}
