import 'package:flutter_app/features/devices/domain/fbm_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FbmCommand', () {
    test('включение строит кадр [0x01, pwm, 0x0D, 0x0A]', () {
      expect(FbmCommand.turnOn(10).toFrameBytes(), [0x01, 25, 0x0d, 0x0a]);
      expect(FbmCommand.turnOn(1).toFrameBytes(), [0x01, 2, 0x0d, 0x0a]);
    });

    test('pwm_byte = int(level / 10 * 25)', () {
      expect(FbmCommand.turnOn(1).pwmByte, 2);
      expect(FbmCommand.turnOn(2).pwmByte, 5);
      expect(FbmCommand.turnOn(5).pwmByte, 12);
      expect(FbmCommand.turnOn(10).pwmByte, 25);
    });

    test('выключение даёт on_off = 0x00 и завершающие CR LF', () {
      final frame = FbmCommand.turnOff().toFrameBytes();
      expect(frame.first, 0x00);
      expect(frame.sublist(2), [0x0d, 0x0a]);
    });

    test('уровень вне диапазона 1..10 отклоняется', () {
      expect(() => FbmCommand.turnOn(0), throwsRangeError);
      expect(() => FbmCommand.turnOn(11), throwsRangeError);
    });

    test('равенство по состоянию', () {
      expect(FbmCommand.turnOn(3), equals(FbmCommand.turnOn(3)));
      expect(FbmCommand.turnOn(3), isNot(equals(FbmCommand.turnOn(4))));
    });
  });
}
