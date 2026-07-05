import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/main_app.dart';

void main() {
  testWidgets('MainApp показывает главный экран приложения', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pump();

    expect(find.text('Лаборатория «Умного сна»'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
