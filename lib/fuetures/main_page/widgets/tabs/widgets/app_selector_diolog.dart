import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/device_session.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/sessions_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/device_display_name.dart';
import 'package:eeg_app_max30003_stm32/features/navigation/navigation_cubit.dart';

/// Диалог выбора устройства для новой вкладки графика.
///
/// Показывает текущие сессии из [SessionsCubit]. Если сессий нет — предлагает
/// перейти на экран «Устройства» и начать поиск. Возвращает выбранную
/// [DeviceSession] — вызывающий код сам решает, как назвать вкладку и какой
/// виджет построить для неё.
Future<DeviceSession?> showAppSelectorDialog(BuildContext context) async {
  final sessionsCubit = context.read<SessionsCubit>();
  final navigationCubit = context.read<NavigationCubit>();
  final sessions = sessionsCubit.state;

  if (sessions.isEmpty) {
    return showDialog<DeviceSession>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Нет подключённых устройств'),
          content: const Text(
            'Сначала подключитесь к устройству на экране «Устройства».',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                navigationCubit.openDevicesAndStartScan();
              },
              child: const Text('Подключиться'),
            ),
          ],
        );
      },
    );
  }

  return showDialog<DeviceSession>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Выберите устройство'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final session in sessions)
              ListTile(
                title: Text(eegDisplayName(session.deviceId)),
                subtitle: Text(_statusText(session.connection.state)),
                onTap: () {
                  Navigator.pop(context, session);
                },
              ),
          ],
        ),
      );
    },
  );
}

String _statusText(DeviceConnectionState state) {
  switch (state.status) {
    case DeviceConnectionStatus.disconnected:
      return 'Не подключено';
    case DeviceConnectionStatus.connecting:
      return 'Подключение…';
    case DeviceConnectionStatus.connected:
      return 'Подключено';
    case DeviceConnectionStatus.lost:
      return 'Связь потеряна';
    case DeviceConnectionStatus.reconnectingManually:
      return 'Переподключение…';
    case DeviceConnectionStatus.failed:
      return 'Не удалось подключиться';
  }
}
