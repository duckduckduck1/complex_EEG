import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_panel_controls.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_panel_plots_choice.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_plots.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/throttled_bloc_builder.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';

/// Одно устройство в мозаике: заголовок со статусами, сигнал и ритмы.
///
/// Панель ничем не владеет — только смотрит в [DeviceViewSession]. Поэтому её
/// можно свободно создавать и выбрасывать при перекладке сетки, не задевая ни
/// поток данных, ни запись.
class DeviceMosaicPanel extends StatefulWidget {
  const DeviceMosaicPanel({
    super.key,
    required this.session,
    required this.title,
    required this.isSelected,
    required this.onSelected,
    required this.onExpand,
    required this.onStartRecording,
    this.refreshInterval = livePlotRefreshInterval,
  });

  final DeviceViewSession session;
  final String title;

  /// Выбранная панель — та, с которой работает нижняя панель инструментов.
  final bool isSelected;
  final VoidCallback onSelected;

  /// Открыть устройство вкладкой: там полный график с осями и зумом.
  final VoidCallback onExpand;

  /// Старт записи спрашивает название эксперимента и фильтры, а диалоги живут
  /// на экране, а не в панели.
  final VoidCallback onStartRecording;

  /// Как часто перерисовывать графики панели; по умолчанию кадровый темп,
  /// общий с графиками вкладки ([livePlotRefreshInterval]).
  ///
  /// Первая версия стояла на 100 мс: нагрузка была ниже, зато задержка стала
  /// видна глазом — на стенде это читалось как подтормаживание, хотя кадры не
  /// терялись.
  final Duration refreshInterval;

  @override
  State<DeviceMosaicPanel> createState() => _DeviceMosaicPanelState();
}

class _DeviceMosaicPanelState extends State<DeviceMosaicPanel> {
  // Состав графиков — местная визуальная мелочь конкретной панели: он ничего
  // не значит для записи и не переживает закрытие вкладки, поэтому живёт в
  // State, а не в bloc.
  MosaicPlotsChoice _plots = const MosaicPlotsChoice();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colorScheme = Theme.of(context).colorScheme;
    // Выбор — через Listener, а не через жест: жест участвует в арене и
    // задерживал бы срабатывание. Здесь это не косметика — распознаватель на
    // панели тормозил бы и все кнопки внутри неё, пока арена не разрешится.
    // Поэтому же разворот сделан явной кнопкой в заголовке, а не двойным
    // кликом: так он ещё и заметнее.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.onSelected(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                widget.isSelected
                    ? colorScheme.primary
                    : colorScheme.outline.withValues(alpha: 0.9),
            width: widget.isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(
                session: session,
                title: widget.title,
                onExpand: widget.onExpand,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _PanelPlots(
                  session: session,
                  refreshInterval: widget.refreshInterval,
                  plots: _plots,
                ),
              ),
              MosaicPanelControls(
                session: session,
                onStartRecording: widget.onStartRecording,
                plots: _plots,
                onTogglePlot:
                    (kind) => setState(() => _plots = _plots.toggle(kind)),
              ),
            ],
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
  const _PanelHeader({
    required this.session,
    required this.title,
    required this.onExpand,
  });

  final DeviceViewSession session;
  final String title;
  final VoidCallback onExpand;

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
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Открыть вкладкой',
                  child: InkResponse(
                    onTap: onExpand,
                    radius: 14,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
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
  const _PanelPlots({
    required this.session,
    required this.refreshInterval,
    required this.plots,
  });

  final DeviceViewSession session;
  final Duration refreshInterval;
  final MosaicPlotsChoice plots;

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
            // остальные графики отвечают на более узкие вопросы и читаются
            // с полоски. Когда сигнал выключен, оставшиеся делят место поровну.
            if (plots.signal)
              Expanded(
                flex: 3,
                child: MosaicSignalPlot(
                  data: session.rtEegDataBloc.filteredSpots,
                ),
              ),
            if (plots.bands) ...[
              if (plots.signal) const SizedBox(height: 4),
              Expanded(
                flex: 2,
                child: MosaicBandsPlot(
                  delta: session.rtEegDataBloc.deltaPower,
                  theta: session.rtEegDataBloc.thetaPower,
                  alpha: session.rtEegDataBloc.alphaPower,
                  beta: session.rtEegDataBloc.betaPower,
                ),
              ),
            ],
            if (plots.spectrum) ...[
              if (plots.signal || plots.bands) const SizedBox(height: 4),
              Expanded(
                flex: 2,
                child: MosaicSpectrumPlot(
                  data: session.rtEegDataBloc.filteredSpectrum,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
