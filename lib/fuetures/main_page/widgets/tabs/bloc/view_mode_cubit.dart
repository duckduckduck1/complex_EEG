import 'package:bloc/bloc.dart';

/// Как показаны открытые устройства.
enum DeviceViewMode {
  /// Одно устройство во весь экран, остальные — лентой вкладок.
  tabs,

  /// Все устройства сеткой панелей сразу.
  mosaic,
}

/// Режим показа устройств.
///
/// Отдельный cubit, а не поле в `TabBloc`: список вкладок и способ их показа —
/// разные вопросы, и смешивать их значит перестраивать вкладки при каждом
/// переключении вида. Сами вкладки от режима не зависят вообще: мозаика и
/// вкладки — два вида на один и тот же список сессий.
class ViewModeCubit extends Cubit<DeviceViewMode> {
  ViewModeCubit() : super(DeviceViewMode.tabs);

  void showTabs() => emit(DeviceViewMode.tabs);

  void showMosaic() => emit(DeviceViewMode.mosaic);

  void toggle() => emit(
    state == DeviceViewMode.tabs ? DeviceViewMode.mosaic : DeviceViewMode.tabs,
  );
}
