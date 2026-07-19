import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/experiment_readme.dart';

/// Тесты на `docs/data-format.md`.
///
/// Документ описывает формат данных для человека, который получил папку с
/// эксперименом и приложения не видел. Он намеренно дублирует словарь меток —
/// иначе читателю пришлось бы искать его в другом месте. Дубль кода в тексте
/// гниёт молча: метку добавят, таблицу не поправят, и человек на другом конце
/// не найдёт расшифровку. Каталог `docs/` в этом проекте однажды уже удаляли
/// именно за это, поэтому здесь дубль удерживается тестом.
void main() {
  final doc = File('docs/data-format.md').readAsStringSync();

  test('в словаре описаны все метки из кода', () {
    final missing = [
      for (final type in defaultLabelTypes)
        if (!doc.contains('`${type.id}`')) type.id,
    ];

    expect(
      missing,
      isEmpty,
      reason:
          'Метки есть в коде, но не описаны в docs/data-format.md: $missing. '
          'Добавьте их в таблицы раздела «Словарь меток».',
    );
  });

  test('в словаре нет меток, которых уже нет в коде', () {
    final knownIds = defaultLabelTypes.map((type) => type.id).toSet();
    // Идентификаторы в тексте — это `snake_case` в обратных кавычках внутри
    // таблиц словаря; берём только тот раздел, чтобы не цеплять примеры кода.
    final dictionary = doc.substring(
      doc.indexOf('## Словарь меток'),
      doc.indexOf('## journal.ndjson'),
    );
    final mentioned =
        RegExp(r'^\| `([a-z_]+)` \|', multiLine: true)
            .allMatches(dictionary)
            .map((match) => match.group(1)!)
            .where((id) => id != 'label_type_id') // шапка таблицы
            .toSet();

    expect(mentioned, isNotEmpty, reason: 'таблицы словаря не разобрались');
    expect(
      mentioned.difference(knownIds),
      isEmpty,
      reason: 'В docs/data-format.md описаны метки, которых нет в коде',
    );
  });

  test('названия меток в документе совпадают с кодом', () {
    final wrong = [
      for (final type in defaultLabelTypes)
        if (!doc.contains('| ${type.displayName} |')) type.id,
    ];

    expect(
      wrong,
      isEmpty,
      reason: 'Названия в docs/data-format.md разошлись с кодом для: $wrong',
    );
  });

  test('readme.txt эксперимента ссылается на существующий документ', () {
    // Ссылка уезжает к человеку вместе с папкой: путь в ней должен указывать
    // на файл, который в репозитории действительно есть.
    expect(readmeDocsUrl, endsWith('docs/data-format.md'));
    expect(File('docs/data-format.md').existsSync(), isTrue);
  });
}
