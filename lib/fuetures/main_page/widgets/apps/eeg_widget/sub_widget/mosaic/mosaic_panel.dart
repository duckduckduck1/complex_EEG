import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_plots.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/throttled_bloc_builder.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';

/// Одно устройство в мозаике: заголовок со статусами, сигнал и ритмы.
///
/// Панель ничем не владеет — только смотрит в [DeviceViewSession]. Поэтому её
/// можно свободно создавать и выбрасывать при перекладке сетки, не задевая ни
/// поток данных, ни запись.
class DeviceMosaicPanel extends StatelessWidget {
  const DeviceMosaicPanel({
    super.key,
    required this.session,
    required this.title,
    required this.isSelected,
    required this.onSelected,
    required this.onExpand,
    this.refreshInterval = const Duration(milliseconds: 100),
  });

  final DeviceViewSession session;
  final String title;

  /// Выбранная панель — та, с которой работает нижняя панель инструментов.
  final bool isSelected;
  final VoidCallback onSelected;

  /// Открыть устройство вкладкой: там полный график с осями и зумом.
  final VoidCallback onExpand;

  /// Как часто перерисовывать графики панели. По умолчанию 10 кадров в секунду:
  /// на панели в несколько сотен пикселей разницы с 250 не видно, а нагрузка
  /// отличается в разы.
  final Duration refreshInterval;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Выбор — через Listener, а не через onTap: рядом живёт распознаватель
    // двойного клика, и любой жест из арены (включая onTapDown) ждал бы её
    // разрешения — треть секунды задержки на каждое переключение панели.
    // Listener в арене не участвует и срабатывает сразу. Двойной клик при этом
    // сначала выберет панель, потом развернёт — ровно то, чего ждёшь.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onSelected(),
      child: GestureDetector(
        // Кликается вся панель целиком: по умолчанию хит-тест уходит ребёнку,
        // а в середине панели график с выключенными касаниями — попасть можно
        // было бы только в рамку.
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onExpand,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.outline.withValues(alpha: 0.9),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PanelHeader(session: session, title: title),
                const SizedBox(height: 6),
                Expanded(
                  child: _PanelPlots(
                    session: session,
                    refreshInterval: refreshInterval,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Имя устройства, состояние связи и таймер записи.
///
/// Слушает bloc'и записи и подключения напрямую: они меняются редко, и
/// ограничивать их частоту незачем — в отличие от потока отсчётов.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.session, required this.title});

  final DeviceViewSession session;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocBuilder<DeviceConnectionBloc, DeviceConnectionState>(
      bloc: session.connection,
      builder: (context, connectionState) {
        final isConnected =
            connectionState.status == DeviceConnectionStatus.connected;
        return BlocBuilder<RecordingBloc, RecordingState>(
          bloc: session.recordingBloc,
          builder: (context, recordingState) {
            final isRecording =
                recordingState.status == RecordingStatus.recording;
            return Row(
              children: [
                Icon(
                  !isConnected
                      ? Icons.link_off_rounded
                      : isRecording
                      ? Icons.fiber_manual_record
                      : Icons.circle_outlined,
                  size: 13,
                  color:
                      !isConnected
                          ? colorScheme.error
                          : isRecording
                          ? colorScheme.error
                          : colorScheme.outline,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (recordingState.fbmOn)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.lightbulb,
                      size: 13,
                      color: colorScheme.tertiary,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  _statusText(connectionState.status, recordingState),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color:
                        isConnected
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.error,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _statusText(DeviceConnectionStatus status, RecordingState recording) {
    if (status != DeviceConnectionStatus.connected) return 'нет связи';
    return switch (recording.status) {
      RecordingStatus.recording ||
      RecordingStatus.stopping => formatClockFromSamples(recording.sampleCount),
      RecordingStatus.pausedByDisconnect => 'пауза',
      RecordingStatus.preparing => 'старт…',
      _ => 'не пишет',
    };
  }
}

class _PanelPlots extends StatelessWidget {
  const _PanelPlots({required this.session, required this.refreshInterval});

  final DeviceViewSession session;
  final Duration refreshInterval;

  @override
  Widget build(BuildContext context) {
    return ThrottledBlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: session.rtEegDataBloc,
      interval: refreshInterval,
      builder: (context, state) {
        if (state is! DataUpdated) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Сигналу отдаём больше места: на него смотрят в первую очередь,
            // ритмы отвечают на вопрос «спит или нет» и с полоски читаются.
            Expanded(flex: 3, child: MosaicSignalPlot(data: state.filterData)),
            const SizedBox(height: 4),
            Expanded(
              flex: 2,
              child: MosaicBandsPlot(
                delta: state.deltaPower,
                theta: state.thetaPower,
                alpha: state.alphaPower,
                beta: state.betaPower,
              ),
            ),
          ],
        );
      },
    );
  }
}
