import 'package:eeg_app_max30003_stm32/features/recording/domain/experiment_folder_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('обычное название проходит', () {
    expect(validateExperimentFolderName('Мышь 1'), isNull);
    expect(validateExperimentFolderName('ФБМ_Группа1_Контроль'), isNull);
  });

  test('крайние пробелы обрезаются, а не считаются ошибкой', () {
    expect(validateExperimentFolderName('  Мышь 1  '), isNull);
    expect(experimentFolderName('  Мышь 1  '), 'Мышь 1');
  });

  test('пустое название отклоняется', () {
    expect(validateExperimentFolderName(''), isNotNull);
    expect(validateExperimentFolderName('   '), isNotNull);
  });

  test('запрещённые для Windows символы отклоняются', () {
    for (final name in [
      'Мышь/1',
      r'Мышь\1',
      'Мышь:1',
      'Мышь*1',
      'Мышь?1',
      'Мышь"1',
      'Мышь<1',
      'Мышь>1',
      'Мышь|1',
    ]) {
      expect(
        validateExperimentFolderName(name),
        isNotNull,
        reason: 'имя «$name» нельзя использовать как папку',
      );
    }
  });

  test('название не может заканчиваться точкой', () {
    expect(validateExperimentFolderName('Мышь 1.'), isNotNull);
  });

  test('зарезервированные системой имена отклоняются', () {
    expect(validateExperimentFolderName('CON'), isNotNull);
    expect(validateExperimentFolderName('com1'), isNotNull);
    expect(validateExperimentFolderName('NUL.txt'), isNotNull);
  });

  test('слишком длинное название отклоняется', () {
    expect(validateExperimentFolderName('М' * 200), isNotNull);
  });

  test('ExperimentFolderExists объясняет проблему оператору', () {
    expect(
      const ExperimentFolderExists('Мышь 1').toString(),
      contains('Мышь 1'),
    );
  });
}
