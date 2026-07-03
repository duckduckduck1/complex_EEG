import 'package:flutter/material.dart';
import 'package:iot/fuetures/ble_page/widgets/ble_buttons.dart';

class BlePageView extends StatefulWidget {
  const BlePageView({super.key});

  @override
  State<BlePageView> createState() => _BlePageState();
}

class _BlePageState extends State<BlePageView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Поиск устройств"),
        actions: [SwitchExample()],
      ),
    );
  }
}
