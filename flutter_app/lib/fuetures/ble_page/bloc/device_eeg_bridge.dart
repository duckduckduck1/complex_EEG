import 'dart:async';

import 'package:iot/features/devices/data/ble_sample_decoder.dart';
import 'package:iot/features/devices/domain/device_signal_config.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';

/// Мост между [DeviceConnectionBloc] и [RtEegDataBloc].
///
/// Пока подключение находится в статусе `connected`, мост декодирует сырые
/// payload'ы из `connection.activeConnection!.packets` в отсчёты [EegSample]
/// (см. `docs/reference/device_packet.md`) и прокидывает их как
/// `NewEegDataReceived` в живой график. При выходе из `connected` (обрыв,
/// ручное отключение, ошибка) подписка на пакеты отменяется — декодер не
/// переживает разрыв, новый экземпляр создаётся на каждое новое подключение.
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

  void _onConnectionState(DeviceConnectionState state) {
    if (state.status == DeviceConnectionStatus.connected) {
      if (_attached) return;
      final connection = _connection.activeConnection;
      if (connection == null) return;
      _attached = true;
      final decoder = BleSampleDecoder(config: _config);
      _packetsSub = connection.packets.listen((payload) {
        final samples = decoder.addPayload(payload);
        for (final sample in samples) {
          _rtEegDataBloc.add(
            NewEegDataReceived(newEegData: sample.valueMicrovolts.toDouble()),
          );
        }
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
