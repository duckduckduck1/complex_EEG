import 'package:flutter/material.dart';

/// Корневой виджет приложения оператора.
///
/// Пока это только оболочка приложения. BLoC-провайдеры, маршрутизация и экраны
/// фич добавляются следующими слайсами (см. docs/flutter_app/architecture.md).
class OperatorApp extends StatelessWidget {
  const OperatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лаборатория Умного сна — оператор',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Лаборатория Умного сна')),
      body: const Center(
        child: Text('Приложение оператора — каркас в разработке'),
      ),
    );
  }
}
