import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/experiment_readme.dart';

void main() {
  String build() => buildExperimentReadme(
    experimentName: 'Мышь 1',
    experimentId: '01J0000000000000000000',
    labelTypes: const [
      LabelType(
        id: 'sleep',
        displayName: 'Спит',
        kind: AnnotationKind.state,
        colorHex: '#2EE6C8',
        sortOrder: 0,
      ),
      LabelType(
        id: 'noise',
        displayName: 'Наводка',
        kind: AnnotationKind.exclude,
        colorHex: '#FF6B6B',
        sortOrder: 1,
      ),
    ],
  );

  test('readme ведёт к подробному описанию формата', () {
    // Папка уезжает к человеку, который репозиторий не открывал: ссылка —
    // единственный мост от данных к полному описанию формата.
    expect(build(), contains(readmeDocsUrl));
  });

  test('ссылка на описание формата ведёт на main', () {
    // Ветку удалят, и ссылка в уже розданных папках протухнет молча.
    expect(readmeDocsUrl, contains('/blob/main/'));
    expect(readmeDocsUrl, endsWith('docs/data-format.md'));
  });

  test('словарь меток попадает в readme', () {
    final text = build();
    expect(text, contains('sleep — Спит'));
    expect(text, contains('noise — Наводка'));
  });
}
