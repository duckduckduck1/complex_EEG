import 'package:flutter/material.dart';

/// Насколько срочно вмешательство оператора.
enum OperatorMessageKind { info, warning, danger }

/// Кнопка в окне сообщения.
class OperatorMessageAction {
  const OperatorMessageAction({
    required this.label,
    this.onPressed,
    this.isPrimary = false,
  });

  final String label;

  /// Что сделать помимо закрытия окна. Окно закрывается в любом случае.
  final VoidCallback? onPressed;

  /// Главное действие — выделено. «Понятно» главным не бывает: оператор должен
  /// видеть, что от него хотят, а не просто отмахнуться.
  final bool isPrimary;
}

/// Показывает оператору сообщение, которое нельзя пропустить.
///
/// Раньше всё это уезжало в снекбар в левом нижнем углу: он висит несколько
/// секунд и исчезает сам, поэтому человек, отошедший от компьютера или просто
/// смотревший на график, ничего не узнавал.
///
/// Окно модальное и закрывается **только кнопкой** — ни клик мимо, ни Esc его
/// не убирают. Расчёт на оператора, который про BLE ничего не знает: текст
/// говорит, что случилось, чем это грозит эксперименту и что делать, а кнопки
/// предлагают действие, а не одно «ОК».
Future<void> showOperatorMessage(
  BuildContext context, {
  required String title,
  required String message,
  String? deviceLabel,
  OperatorMessageKind kind = OperatorMessageKind.warning,
  List<OperatorMessageAction> actions = const [],
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final accent = switch (kind) {
        OperatorMessageKind.info => theme.colorScheme.primary,
        OperatorMessageKind.warning => theme.colorScheme.tertiary,
        OperatorMessageKind.danger => theme.colorScheme.error,
      };
      final icon = switch (kind) {
        OperatorMessageKind.info => Icons.check_circle_outline,
        OperatorMessageKind.warning => Icons.warning_amber_rounded,
        OperatorMessageKind.danger => Icons.error_outline,
      };

      return PopScope(
        // Esc не должен убирать сообщение о том, что запись встала.
        canPop: false,
        child: AlertDialog(
          icon: Icon(icon, color: accent, size: 32),
          title: Column(
            children: [
              Text(title, textAlign: TextAlign.center),
              if (deviceLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  deviceLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(color: accent),
                ),
              ],
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            for (final action in actions)
              _button(dialogContext, action, accent),
            if (actions.every((action) => !action.isPrimary))
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Понятно'),
              ),
          ],
        ),
      );
    },
  );
}

Widget _button(
  BuildContext context,
  OperatorMessageAction action,
  Color accent,
) {
  void handle() {
    Navigator.of(context).pop();
    action.onPressed?.call();
  }

  if (!action.isPrimary) {
    return TextButton(onPressed: handle, child: Text(action.label));
  }
  return FilledButton(
    onPressed: handle,
    style: FilledButton.styleFrom(backgroundColor: accent),
    child: Text(action.label),
  );
}
