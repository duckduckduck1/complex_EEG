import 'package:flutter/widgets.dart';

/// Сообщает содержимому вкладки, активна ли она сейчас.
///
/// `IndexedStack` держит все вкладки смонтированными и показывает только
/// текущую. Активность здесь определяется **позицией в стеке** (`i ==
/// currentIndex`), а не устройством: два таба могут смотреть на одно и то же
/// подключение, и различать их по нему нельзя.
///
/// Вне стека (например, в тестах) считается активной по умолчанию.
class TabActiveScope extends InheritedWidget {
  const TabActiveScope({super.key, required this.active, required super.child});

  final bool active;

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TabActiveScope>();
    return scope?.active ?? true;
  }

  @override
  bool updateShouldNotify(TabActiveScope oldWidget) =>
      oldWidget.active != active;
}
