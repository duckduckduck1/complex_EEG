import 'package:equatable/equatable.dart';

/// Настройки фильтров живого графика.
///
/// Неизменяемая: раньше её меняли **на месте**, и общий экземпляр ходил по рукам
/// между виджетом настроек, bloc'ом и вкладкой. Из-за этого изменение никто не
/// мог заметить — объект оставался тем же, — и приходилось городить счётчик
/// ревизии и пересоздавать виджет по ключу, чтобы панель перечитала значения.
/// Со значением, которое сравнивается по содержимому, всё это не нужно:
/// изменилось — приехало новое.
class FillterSettings extends Equatable {
  const FillterSettings({
    this.lp = 40,
    this.hp = 0.5,
    this.notch = 50,
    this.isLpOn = false,
    this.isHpOn = false,
    this.isNotchOn = false,
  });

  final double lp;
  final double hp;
  final double notch;
  final bool isLpOn;
  final bool isHpOn;
  final bool isNotchOn;

  FillterSettings copyWith({
    double? lp,
    double? hp,
    double? notch,
    bool? isLpOn,
    bool? isHpOn,
    bool? isNotchOn,
  }) {
    return FillterSettings(
      lp: lp ?? this.lp,
      hp: hp ?? this.hp,
      notch: notch ?? this.notch,
      isLpOn: isLpOn ?? this.isLpOn,
      isHpOn: isHpOn ?? this.isHpOn,
      isNotchOn: isNotchOn ?? this.isNotchOn,
    );
  }

  @override
  List<Object?> get props => [lp, hp, notch, isLpOn, isHpOn, isNotchOn];
}
