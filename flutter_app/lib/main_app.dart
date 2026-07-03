import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_layout/views/main_layout_view.dart';
import 'package:iot/theme.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: theme,
      home: MainLayout(),
      debugShowCheckedModeBanner: false,
    );
  }
}
