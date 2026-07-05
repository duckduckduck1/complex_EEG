import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';

void main() {
  late NavigationCubit cubit;

  setUp(() {
    cubit = NavigationCubit();
  });

  tearDown(() async {
    await cubit.close();
  });

  test('начальное состояние — раздел «Главная» без флагов', () {
    expect(cubit.state.sectionIndex, 0);
    expect(cubit.state.autoStartDiscoveryRequested, isFalse);
    expect(cubit.state.pendingTabDeviceId, isNull);
  });

  test('selectSection меняет индекс раздела', () {
    cubit.selectSection(2);

    expect(cubit.state.sectionIndex, 2);
  });

  test(
    'openDevicesAndStartScan переключает на «Устройства» и просит автостарт скана',
    () {
      cubit.openDevicesAndStartScan();

      expect(cubit.state.sectionIndex, 1);
      expect(cubit.state.autoStartDiscoveryRequested, isTrue);
    },
  );

  test('discoveryAutoStartConsumed сбрасывает флаг автостарта', () {
    cubit.openDevicesAndStartScan();
    cubit.discoveryAutoStartConsumed();

    expect(cubit.state.autoStartDiscoveryRequested, isFalse);
    // Раздел остаётся выбранным — сбрасывается только флаг.
    expect(cubit.state.sectionIndex, 1);
  });

  test(
    'setPendingTab запоминает устройство, pendingTabConsumed сбрасывает',
    () {
      const deviceId = BleDeviceId('AA:BB:CC');

      cubit.setPendingTab(deviceId);
      expect(cubit.state.pendingTabDeviceId, deviceId);

      cubit.pendingTabConsumed();
      expect(cubit.state.pendingTabDeviceId, isNull);
    },
  );
}
