import 'package:flutter_app/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OperatorApp строится и показывает каркас', (tester) async {
    await tester.pumpWidget(const OperatorApp());
    expect(find.text('Лаборатория Умного сна'), findsOneWidget);
  });
}
