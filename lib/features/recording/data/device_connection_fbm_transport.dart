import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

class DeviceConnectionFbmTransport implements FbmTransport {
  const DeviceConnectionFbmTransport({required DeviceConnectionBloc connection})
    : _connection = connection;

  final DeviceConnectionBloc _connection;

  @override
  Future<bool> setLed({required bool on, required int pwmByte}) async {
    final connection = _connection.activeConnection;
    if (connection == null) {
      return false;
    }
    await connection.writeCommand([on ? 0x01 : 0x00, pwmByte, 0x0D, 0x0A]);
    return true;
  }
}
