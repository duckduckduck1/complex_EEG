import 'package:bloc/bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

/// Настройки живого графика одной вкладки: состав графиков и фильтры.
///
/// Отдельный владелец нужен, потому что настройки читают трое: панель фильтров,
/// панель состава и сам [RtEegDataBloc]. Раньше их роль играл изменяемый объект,
/// который все трое держали по ссылке и меняли на месте — а чтобы кто-то
/// заметил изменение, вкладка дёргала счётчик ревизии и пересоздавала виджет по
/// ключу. Теперь настройки — обычное состояние: изменились, все подписчики
/// перестроились.
class EegSettingsCubit extends Cubit<EegSettings> {
  EegSettingsCubit() : super(const EegSettings.initial());

  void setFilters(FillterSettings filters) =>
      emit(state.copyWith(fillterSettings: filters));

  void setShowing(EegIsShowingSettings showing) =>
      emit(state.copyWith(eegIsShowingSettings: showing));

  /// Переносит фильтры, выбранные при старте записи, на живой график.
  ///
  /// Иначе оператор выставляет их дважды: один раз в диалоге старта (для
  /// записи) и второй раз руками в панели (для картинки).
  void applyRecordingFilters(RecordingFilters filters) {
    emit(
      state.copyWith(
        fillterSettings: FillterSettings(
          lp: filters.lpHz,
          hp: filters.hpHz,
          notch: filters.notchHz,
          isLpOn: filters.isLpEnabled,
          isHpOn: filters.isHpEnabled,
          isNotchOn: filters.isNotchEnabled,
        ),
      ),
    );
  }
}
