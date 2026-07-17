import 'dart:async';

import 'package:iot/features/devices/data/ble_sample_decoder.dart';
import 'package:iot/features/devices/domain/device_signal_config.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';

class RecordingBridge {
  RecordingBridge({
    required DeviceConnectionBloc connection,
    required RecordingBloc recordingBloc,
    DeviceSignalConfig config = DeviceSignalConfig.stand1,
  }) : _connection = connection,
       _recordingBloc = recordingBloc,
       _config = config {
    _connectionSub = _connection.stream.listen(_onConnectionState);
    _onConnectionState(_connection.state);
  }

  final DeviceConnectionBloc _connection;
  final RecordingBloc _recordingBloc;
  final DeviceSignalConfig _config;

  StreamSubscription<DeviceConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _packetsSub;
  bool _attached = false;

  void _onConnectionState(DeviceConnectionState state) {
    if (state.status == DeviceConnectionStatus.connected) {
      if (_attached) return;
      final connection = _connection.activeConnection;
      if (connection == null) return;

      _recordingBloc.add(const RecordingConnectionResumed());
      _attached = true;
      final decoder = BleSampleDecoder(config: _config);
      _packetsSub = connection.packets.listen((payload) {
        final samples = decoder
            .addPayload(payload)
            .map((sample) => sample.valueMicrovolts)
            .toList(growable: false);
        if (samples.isNotEmpty) {
          _recordingBloc.add(RecordingSamplesReceived(samples));
        }
      });
      return;
    }

    _detach();
    if (state.status == DeviceConnectionStatus.lost ||
        state.status == DeviceConnectionStatus.failed) {
      _recordingBloc.add(const RecordingConnectionLost());
    }
  }

  void _detach() {
    _attached = false;
    _packetsSub?.cancel();
    _packetsSub = null;
  }

  Future<void> dispose() async {
    _detach();
    await _connectionSub?.cancel();
    _connectionSub = null;
  }
}
