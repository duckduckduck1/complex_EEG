import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/recording/presentation/recording_start_dialog.dart';

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => showRecordingStartDialog(context),
              child: const Text('открыть'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('все три фильтра включены при открытии', (tester) async {
    // Оператор — биолог, а не инженер: решать, нужен ли ему режекторный фильтр
    // на 50 Гц, ему не с чем. Выключенный notch — почти наверняка забытый notch,
    // и в записи останется сетевая наводка, которую уже не убрать.
    await openDialog(tester);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(3), reason: 'LP, HP и Notch');
    expect(
      switches.map((s) => s.value),
      everyElement(isTrue),
      reason: 'дефолт не должен молча откатиться в выключенный',
    );
  });

  testWidgets('частоты фильтров заполнены значениями по умолчанию', (
    tester,
  ) async {
    // Включённый переключатель без частоты был бы ловушкой: оператор нажал бы
    // «Начать» и получил фильтр непонятно с какой границей.
    await openDialog(tester);

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    final values = fields.map((f) => f.controller?.text).toList();
    expect(values, containsAll(<String>['40', '0.5', '50']));
  });
}
