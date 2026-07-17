import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/main_app.dart';

void main() {
  testWidgets('MainApp показывает главный экран приложения', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pump();

    expect(find.text('Лаборатория «Умного сна»'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
