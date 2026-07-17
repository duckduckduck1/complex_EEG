import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bridge.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/ble_page/bloc/device_eeg_bridge.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';

/// Вкладка живого графика одного подключённого устройства.
///
/// Владеет визуализацией ([RtEegDataBloc] + [DeviceEegBridge]) и закрывает её
/// в [State.dispose]. НЕ владеет подключением: [connection] принадлежит
/// `SessionsCubit`, закрытие вкладки не отключает устройство
/// (docs/flutter_app/architecture.md, «Изоляция нескольких устройств»).
///
/// `IndexedStack` держит все вкладки живыми, поэтому неактивная вкладка строила
/// бы график впустую (offstage-виджет всё равно перестраивается на каждый emit).
/// Пока вкладка неактивна, вместо [EegWidget] строится лёгкая заглушка —
/// перестройки и перерисовки графика прекращаются. **Пайплайн данных при этом
/// не трогается**: [RtEegDataBloc] продолжает считать, поэтому при возврате на
/// вкладку график сразу живой, без зависания. Запись ведёт отдельный
/// [RecordingBridge] и она идёт всегда.
class DeviceEegTab extends StatefulWidget {
  const DeviceEegTab({
    super.key,
    required this.connection,
    required this.recordingBloc,
  });

  /// BLoC подключения устройства; жизненным циклом владеет `SessionsCubit`.
  final DeviceConnectionBloc connection;
  final RecordingBloc recordingBloc;

  @override
  State<DeviceEegTab> createState() => _DeviceEegTabState();
}

class _DeviceEegTabState extends State<DeviceEegTab> {
  late final RtEegDataBloc _rtEegDataBloc;
  late final DeviceEegBridge _bridge;
  late final RecordingBridge _recordingBridge;
  late final StreamSubscription<RecordingState> _recordingSub;
  RecordingStatus _lastRecordingStatus = RecordingStatus.idle;

  @override
  void initState() {
    super.initState();
    _rtEegDataBloc = RtEegDataBloc(250);
    _bridge = DeviceEegBridge(
      connection: widget.connection,
      rtEegDataBloc: _rtEegDataBloc,
    );
    _recordingBridge = RecordingBridge(
      connection: widget.connection,
      recordingBloc: widget.recordingBloc,
    );
    _recordingSub = widget.recordingBloc.stream.listen((state) {
      if (_lastRecordingStatus == RecordingStatus.preparing &&
          state.status == RecordingStatus.recording) {
        _rtEegDataBloc.add(RtEegResetRequested());
      }
      _lastRecordingStatus = state.status;
    });
  }

  @override
  void dispose() {
    // Только визуализация: мост и график. connection.close() НЕ вызывается.
    _recordingSub.cancel();
    _bridge.dispose();
    _recordingBridge.dispose();
    widget.recordingBloc.close();
    _rtEegDataBloc.close();
    super.dispose();
  }

  /// Активна ли эта вкладка сейчас. Идентичность вкладки — по её [connection]:
  /// сравнивать по индексу нельзя, индексы сдвигаются при закрытии соседних.
  bool _isActiveTab(TabState state) {
    final index = state.connectionBlocs.indexOf(widget.connection);
    return index >= 0 && index == state.currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabBloc, TabState>(
      buildWhen:
          (previous, current) =>
              _isActiveTab(previous) != _isActiveTab(current),
      builder: (context, state) {
        if (!_isActiveTab(state)) {
          return const _InactiveTabPlaceholder();
        }
        return EegWidget(rtEegDataBloc: _rtEegDataBloc);
      },
    );
  }
}

/// Заглушка неактивной вкладки: график не строится и не перерисовывается.
/// Обычно не видна (вкладка offstage в `IndexedStack`) — её задача снять
/// нагрузку с перестройки графика, а не что-то показать.
class _InactiveTabPlaceholder extends StatelessWidget {
  const _InactiveTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.pause_circle_outline,
            size: 18,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            'Вкладка неактивна — график на паузе',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
