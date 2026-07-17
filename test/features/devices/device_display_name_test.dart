import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_device.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/device_display_name.dart';

void main() {
  test('берёт последние 2 hex-символа MAC и переводит в верхний регистр', () {
    expect(
      eegDisplayName(const BleDeviceId('AA:BB:CC:DD:EE:4f')),
      'EEG-device:4F',
    );
  });

  test('короткая строка не падает — используется целиком', () {
    expect(eegDisplayName(const BleDeviceId('A')), 'EEG-device:A');
  });

  test('пустая строка не падает', () {
    expect(eegDisplayName(const BleDeviceId('')), 'EEG-device:');
  });

  test('разные устройства с одинаковым префиксом различаются по хвосту', () {
    expect(
      eegDisplayName(const BleDeviceId('11:22:33:44:55:01')),
      isNot(eegDisplayName(const BleDeviceId('11:22:33:44:55:02'))),
    );
  });
}
