import 'dart:async';

import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bridge.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/ble_page/bloc/device_eeg_bridge.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';

/// Вкладка живого графика одного подключённого устройства.
///
/// Владеет визуализацией ([RtEegDataBloc] + [DeviceEegBridge]) и закрывает её
/// в [State.dispose]. НЕ владеет подключением: [connection] принадлежит
/// `SessionsCubit`, закрытие вкладки не отключает устройство
/// (docs/flutter_app/architecture.md, «Изоляция нескольких устройств»).
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

  @override
  Widget build(BuildContext context) {
    return EegWidget(rtEegDataBloc: _rtEegDataBloc);
  }
}
