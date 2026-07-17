import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../devices/domain/ble_device.dart';

/// Неизменяемое состояние [NavigationCubit].
class NavigationState extends Equatable {
  const NavigationState({
    this.sectionIndex = 0,
    this.autoStartDiscoveryRequested = false,
    this.pendingTabDeviceId,
  });

  /// Индекс раздела: 0 — Главная, 1 — Устройства, 2 — Настройки.
  final int sectionIndex;

  /// Экран «Устройства» должен начать поиск сразу после открытия.
  ///
  /// Флаг устанавливается навигацией, но саму команду «начать скан»
  /// выполняет экран, увидевший этот флаг — навигация не выполняет бизнес-
  /// операций (docs/flutter_app/architecture.md).
  final bool autoStartDiscoveryRequested;

  /// Устройство, вкладку которого нужно открыть/выделить при следующем
  /// удобном случае. Выставляется автопредложением на экране «Устройства»
  /// и ручным выбором в `app_selector_diolog.dart`; считывается и сбрасывается
  /// `MainPage` (`lib/fuetures/main_page/views/main_page_view.dart`).
  final BleDeviceId? pendingTabDeviceId;

  static const Object _unset = Object();

  NavigationState copyWith({
    int? sectionIndex,
    bool? autoStartDiscoveryRequested,
    Object? pendingTabDeviceId = _unset,
  }) {
    return NavigationState(
      sectionIndex: sectionIndex ?? this.sectionIndex,
      autoStartDiscoveryRequested:
          autoStartDiscoveryRequested ?? this.autoStartDiscoveryRequested,
      pendingTabDeviceId:
          pendingTabDeviceId == _unset
              ? this.pendingTabDeviceId
              : pendingTabDeviceId as BleDeviceId?,
    );
  }

  @override
  List<Object?> get props => [
    sectionIndex,
    autoStartDiscoveryRequested,
    pendingTabDeviceId,
  ];
}

/// Управляет выбранным разделом приложения и межэкранными командами навигации.
///
/// Навигация не выполняет бизнес-операций (docs/flutter_app/architecture.md):
/// она только переключает раздел и оставляет для целевого экрана флаг-
/// намерение, который экран сам превращает в конкретное действие.
class NavigationCubit extends Cubit<NavigationState> {
  NavigationCubit() : super(const NavigationState());

  /// Выбрать раздел приложения по индексу.
  void selectSection(int index) => emit(state.copyWith(sectionIndex: index));

  /// Переключить на экран «Устройства» и попросить его запустить поиск —
  /// сама команда "начать скан" выполняется экраном, увидевшим этот флаг
  /// (навигация не выполняет бизнес-операций, docs/flutter_app/architecture.md).
  void openDevicesAndStartScan() =>
      emit(state.copyWith(sectionIndex: 1, autoStartDiscoveryRequested: true));

  /// Экран «Устройства» подтверждает, что запрос на автозапуск поиска
  /// обработан — флаг сбрасывается, чтобы не запускать скан повторно.
  void discoveryAutoStartConsumed() =>
      emit(state.copyWith(autoStartDiscoveryRequested: false));

  /// Оставить намерение открыть/выделить вкладку устройства [id].
  void setPendingTab(BleDeviceId id) =>
      emit(state.copyWith(pendingTabDeviceId: id));

  /// Подтвердить, что намерение открыть вкладку обработано.
  void pendingTabConsumed() => emit(state.copyWith(pendingTabDeviceId: null));
}
