import 'package:equatable/equatable.dart';

/// Команда управления светодиодом фотобиомодуляции (ФБМ).
///
/// Кадр команды — 4 байта `[on_off, pwm_byte, 0x0D, 0x0A]`, записывается в ту же
/// BLE-характеристику, что и приём сигнала (см. docs/reference/device_packet.md).
/// Каждое включение/выключение и смена яркости — событие эксперимента.
class FbmCommand extends Equatable {
  const FbmCommand._({required this.isOn, required this.level});

  /// Включить ФБМ на уровне яркости [level] (1..10).
  factory FbmCommand.turnOn(int level) {
    RangeError.checkValueInInterval(level, minLevel, maxLevel, 'level');
    return FbmCommand._(isOn: true, level: level);
  }

  /// Выключить ФБМ. [level] сохраняется для журнала, но на яркость не влияет.
  factory FbmCommand.turnOff({int level = minLevel}) {
    RangeError.checkValueInInterval(level, minLevel, maxLevel, 'level');
    return FbmCommand._(isOn: false, level: level);
  }

  /// Включена ли стимуляция.
  final bool isOn;

  /// Уровень яркости, заданный пользователем (1..10).
  final int level;

  /// Минимальный уровень яркости.
  static const int minLevel = 1;

  /// Максимальный уровень яркости.
  static const int maxLevel = 10;

  /// Завершающий байт кадра CR, обязателен по контракту.
  static const int crByte = 0x0d;

  /// Завершающий байт кадра LF, обязателен по контракту.
  static const int lfByte = 0x0a;

  /// Байт яркости: `pwm_byte = int(level / 10 * 25)` (диапазон ~2..25).
  int get pwmByte => (level / 10 * 25).toInt();

  /// 4-байтовый кадр команды для записи в характеристику устройства.
  List<int> toFrameBytes() => [isOn ? 0x01 : 0x00, pwmByte, crByte, lfByte];

  @override
  List<Object?> get props => [isOn, level];
}
