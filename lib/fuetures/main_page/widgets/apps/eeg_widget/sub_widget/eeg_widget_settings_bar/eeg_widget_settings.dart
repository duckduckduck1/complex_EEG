import 'package:equatable/equatable.dart';

/// Какие графики показывает вкладка.
///
/// Неизменяемая по той же причине, что и настройки фильтров: раньше общий
/// экземпляр меняли на месте, и смену состава нельзя было заметить сравнением.
class EegIsShowingSettings extends Equatable {
  const EegIsShowingSettings({
    this.isBandsShowing = false,
    this.isFftShowing = false,
    this.isFilterShowing = false,
  });

  final bool isFftShowing;
  final bool isFilterShowing;
  final bool isBandsShowing;

  EegIsShowingSettings copyWith({
    bool? isFftShowing,
    bool? isFilterShowing,
    bool? isBandsShowing,
  }) {
    return EegIsShowingSettings(
      isFftShowing: isFftShowing ?? this.isFftShowing,
      isFilterShowing: isFilterShowing ?? this.isFilterShowing,
      isBandsShowing: isBandsShowing ?? this.isBandsShowing,
    );
  }

  @override
  List<Object?> get props => [isFftShowing, isFilterShowing, isBandsShowing];
}
