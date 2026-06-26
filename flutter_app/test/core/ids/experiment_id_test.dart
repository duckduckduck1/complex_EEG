import 'package:flutter_app/core/ids/experiment_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExperimentId', () {
    test('generate даёт exp_<ULID> по серверному regex', () {
      final id = ExperimentId.generate();
      expect(id.value.startsWith('exp_'), isTrue);
      expect(ExperimentId.isValid(id.value), isTrue);
      expect(id.value.length, 'exp_'.length + 26);
    });

    test('parse принимает валидное значение', () {
      const raw = 'exp_01HX7M8M9RF2K0Z6GNZ6D7Q7AP';
      final result = ExperimentId.parse(raw);
      expect(result.isOk, isTrue);
      expect(result.valueOrNull?.value, raw);
    });

    test('parse отклоняет недопустимые символы', () {
      final result = ExperimentId.parse('exp/with slash');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull?.code, 'validation.experiment_id_invalid');
    });

    test('parse отклоняет пустую строку и длину больше 64', () {
      expect(ExperimentId.parse('').isErr, isTrue);
      expect(ExperimentId.parse('a' * 65).isErr, isTrue);
      expect(ExperimentId.parse('a' * 64).isOk, isTrue);
    });

    test('равенство по значению', () {
      final a = ExperimentId.parse('exp_1').valueOrNull;
      final b = ExperimentId.parse('exp_1').valueOrNull;
      expect(a, equals(b));
    });
  });
}
