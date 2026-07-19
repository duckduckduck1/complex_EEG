import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../devices/presentation/blocs/device_connection_bloc.dart';
import '../devices/presentation/blocs/device_connection_event.dart';
import '../devices/presentation/blocs/device_connection_state.dart';
import '../recording/application/recording_bloc.dart';
import '../recording/domain/recording_models.dart';

/// Окно обрыва связи: оператор жмёт «Переподключить» прямо здесь и здесь же
/// видит, что происходит.
///
/// Переподключение остаётся **ручным** — приложение само не стучится в
/// устройство. Но попытки считаются, и с каждым провалом совет становится
/// конкретнее: сначала просто «попробуйте ещё раз», после трёх неудач —
/// проверить устройство, после пяти — перезагрузить его.
///
/// Чего окно **не** советует, так это останавливать запись. Пауза по обрыву
/// ничего не теряет: записанное уже на диске, а после переподключения
/// эксперимент продолжается новым отрезком. Остановка же необратима — поэтому
/// она есть отдельной кнопкой для того, кто решил сдаться, но никогда не
/// предлагается как решение.
Future<void> showReconnectDialog(
  BuildContext context, {
  required String deviceLabel,
  required DeviceConnectionBloc connection,
  required RecordingBloc recording,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder:
        (dialogContext) => PopScope(
          canPop: false,
          child: _ReconnectDialog(
            deviceLabel: deviceLabel,
            connection: connection,
            recording: recording,
          ),
        ),
  );
}

class _ReconnectDialog extends StatefulWidget {
  const _ReconnectDialog({
    required this.deviceLabel,
    required this.connection,
    required this.recording,
  });

  final String deviceLabel;
  final DeviceConnectionBloc connection;
  final RecordingBloc recording;

  @override
  State<_ReconnectDialog> createState() => _ReconnectDialogState();
}

class _ReconnectDialogState extends State<_ReconnectDialog> {
  /// Сколько раз оператор нажал «Переподключить» и не вышло.
  int _failedAttempts = 0;

  /// После скольких неудач подсказка становится конкретнее.
  static const int _checkDeviceAfter = 3;
  static const int _restartDeviceAfter = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<DeviceConnectionBloc, DeviceConnectionState>(
      bloc: widget.connection,
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        if (state.status == DeviceConnectionStatus.lost ||
            state.status == DeviceConnectionStatus.failed) {
          // Попытка закончилась ничем — считаем её и показываем следующий совет.
          setState(() => _failedAttempts++);
        }
      },
      builder: (context, state) {
        final isTrying =
            state.status == DeviceConnectionStatus.reconnectingManually;
        final isConnected = state.isConnected;
        final accent =
            isConnected ? theme.colorScheme.primary : theme.colorScheme.error;

        return AlertDialog(
          icon:
              isTrying
                  ? const SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                  : Icon(
                    isConnected
                        ? Icons.check_circle_outline
                        : Icons.link_off_rounded,
                    color: accent,
                    size: 32,
                  ),
          title: Column(
            children: [
              Text(_title(isTrying, isConnected), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                widget.deviceLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(color: accent),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              _message(isTrying, isConnected),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: _actions(context, isTrying, isConnected, accent),
        );
      },
    );
  }

  String _title(bool isTrying, bool isConnected) {
    if (isConnected) return 'Связь восстановлена';
    if (isTrying) return 'Пробуем переподключиться…';
    if (_failedAttempts == 0) return 'Связь с устройством потеряна';
    return 'Переподключиться не удалось';
  }

  String _message(bool isTrying, bool isConnected) {
    final isRecording = isRecordingBusy(widget.recording.state.status);

    if (isConnected) {
      return isRecording
          ? 'Запись продолжается с нового отрезка. Разрыв отмечен в файле '
              'эксперимента: пропущенное время не заполняется выдуманными '
              'данными.'
          : 'Данные снова идут, график ожил.';
    }
    if (isTrying) {
      return 'Идёт попытка ${_failedAttempts + 1}. Это занимает несколько '
          'секунд — подождите, пожалуйста.';
    }

    final tail =
        isRecording
            ? '\n\nЗапись всё это время стоит на паузе и ничего не теряет: '
                'записанное уже сохранено, а после переподключения эксперимент '
                'продолжится сам.'
            : '';

    if (_failedAttempts == 0) {
      return 'Данные с устройства больше не приходят.\n\n'
          'Нажмите «Переподключить» — обычно этого достаточно.$tail';
    }
    if (_failedAttempts < _checkDeviceAfter) {
      return 'Устройство не ответило. Попробуйте ещё раз — иногда связь '
          'подхватывается со второго или третьего раза.$tail';
    }
    if (_failedAttempts < _restartDeviceAfter) {
      return 'Не удалось $_failedAttempts раза подряд. Подойдите к клетке и '
          'проверьте устройство: горит ли на нём индикатор, не разрядился ли '
          'аккумулятор, не отошёл ли провод. Потом попробуйте снова.$tail';
    }
    return 'Устройство не отвечает после $_failedAttempts попыток.\n\n'
        'Выключите его и включите заново, а потом нажмите «Переподключить» '
        'ещё раз.$tail';
  }

  List<Widget> _actions(
    BuildContext context,
    bool isTrying,
    bool isConnected,
    Color accent,
  ) {
    if (isConnected) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: const Text('Продолжить работу'),
        ),
      ];
    }

    return [
      // Пока идёт попытка, кнопка неактивна: два переподключения подряд ничего
      // не ускорят, а оператор решит, что первое не сработало.
      FilledButton(
        onPressed:
            isTrying
                ? null
                : () => widget.connection.add(const ManualReconnectRequested()),
        style: FilledButton.styleFrom(backgroundColor: accent),
        child: Text(
          _failedAttempts == 0 ? 'Переподключить' : 'Попробовать ещё раз',
        ),
      ),
      // Остановка появляется только когда оператор уже намучился, и никогда не
      // предлагается текстом: она необратима, а пауза — нет.
      if (!isTrying &&
          _failedAttempts >= _restartDeviceAfter &&
          isRecordingBusy(widget.recording.state.status))
        TextButton(
          onPressed: () {
            widget.recording.add(const RecordingStopRequested());
            Navigator.of(context).pop();
          },
          child: const Text('Завершить эксперимент'),
        ),
      TextButton(
        onPressed: isTrying ? null : () => Navigator.of(context).pop(),
        child: const Text('Закрыть'),
      ),
    ];
  }
}
