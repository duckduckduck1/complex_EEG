import 'dart:async';

import 'package:eeg_app_max30003_stm32/features/devices/data/ble_sample_decoder.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/device_signal_config.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';

/// Мост между [DeviceConnectionBloc] и [RtEegDataBloc].
///
/// Пока подключение находится в статусе `connected`, мост декодирует сырые
/// payload'ы из `connection.activeConnection!.packets` в отсчёты [EegSample]
/// (см. `docs/reference/device_packet.md`) и прокидывает их пачкой как
/// `NewEegSamplesReceived` в живой график. При выходе из `connected` (обрыв,
/// ручное отключение, ошибка) подписка на пакеты отменяется — декодер не
/// переживает разрыв, новый экземпляр создаётся на каждое новое подключение.
///
/// [setActive] гасит визуализацию, когда вкладка устройства неактивна: пока
/// `active == false`, пакеты не декодируются и график не обновляется, чтобы
/// скрытые вкладки не жгли CPU на FFT и фильтрах. **Запись это не затрагивает** —
/// её ведёт отдельный `RecordingBridge`, который работает всегда.
///
/// Мост не выполняет автоматическое переподключение — это уже задача
/// [DeviceConnectionBloc]; он только реагирует на его состояния.
class DeviceEegBridge {
  DeviceEegBridge({
    required DeviceConnectionBloc connection,
    required RtEegDataBloc rtEegDataBloc,
    DeviceSignalConfig config = DeviceSignalConfig.stand1,
  }) : _connection = connection,
       _rtEegDataBloc = rtEegDataBloc,
       _config = config {
    _connectionSub = _connection.stream.listen(_onConnectionState);
    // Состояние на момент подписки могло уже быть connected.
    _onConnectionState(_connection.state);
  }

  final DeviceConnectionBloc _connection;
  final RtEegDataBloc _rtEegDataBloc;
  final DeviceSignalConfig _config;

  StreamSubscription<DeviceConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _packetsSub;
  bool _attached = false;
  bool _active = true;

  /// Включает/выключает подачу данных в живой график. Неактивная вкладка
  /// перестаёт кормить [RtEegDataBloc]; подписка на пакеты остаётся, но payload
  /// просто отбрасывается, поэтому включение обратно мгновенно.
  void setActive({required bool active}) {
    _active = active;
  }

  void _onConnectionState(DeviceConnectionState state) {
    if (state.status == DeviceConnectionStatus.connected) {
      if (_attached) return;
      final connection = _connection.activeConnection;
      if (connection == null) return;
      _attached = true;
      final decoder = BleSampleDecoder(config: _config);
      _packetsSub = connection.packets.listen((payload) {
        // Декодируем всегда, чтобы не сбить побайтовое выравнивание при возврате
        // на вкладку; в неактивном состоянии просто не кормим график.
        final samples = decoder.addPayload(payload);
        if (!_active || samples.isEmpty) return;
        _rtEegDataBloc.add(
          NewEegSamplesReceived(
            samples: [
              for (final sample in samples) sample.valueMicrovolts.toDouble(),
            ],
          ),
        );
      });
    } else {
      _detach();
    }
  }

  void _detach() {
    _attached = false;
    _packetsSub?.cancel();
    _packetsSub = null;
  }

  /// Отменяет все подписки моста. Не закрывает переданные BLoC — их жизненным
  /// циклом владеет вызывающий код (экран).
  Future<void> dispose() async {
    _detach();
    await _connectionSub?.cancel();
    _connectionSub = null;
  }
}
