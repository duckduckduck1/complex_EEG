import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:eeg_app_max30003_stm32/main_app.dart';

void main() {
  if (kDebugMode) {
    // Диагностика медленного BLE-поиска: verbose-логи flutter_blue_plus
    // только в debug-сборках. Dart-уровень логов применяется синхронно, а
    // платформенный вызов доедет уже после инициализации биндинга в runApp,
    // поэтому Future осознанно не ожидается.
    unawaited(FlutterBluePlus.setLogLevel(LogLevel.verbose));
  }
  runApp(const MainApp());
}
