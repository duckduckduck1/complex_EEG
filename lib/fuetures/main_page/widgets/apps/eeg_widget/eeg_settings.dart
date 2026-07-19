import 'package:equatable/equatable.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

/// Все настройки живого графика одной вкладки: что показываем и как фильтруем.
class EegSettings extends Equatable {
  const EegSettings(this.eegIsShowingSettings, this.fillterSettings);

  const EegSettings.initial()
    : eegIsShowingSettings = const EegIsShowingSettings(),
      fillterSettings = const FillterSettings();

  final EegIsShowingSettings eegIsShowingSettings;
  final FillterSettings fillterSettings;

  EegSettings copyWith({
    EegIsShowingSettings? eegIsShowingSettings,
    FillterSettings? fillterSettings,
  }) {
    return EegSettings(
      eegIsShowingSettings ?? this.eegIsShowingSettings,
      fillterSettings ?? this.fillterSettings,
    );
  }

  @override
  List<Object?> get props => [eegIsShowingSettings, fillterSettings];
}
