import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

class EegSettings {
  EegIsShowingSettings eegIsShowingSettings;
  FillterSettings fillterSettings;
  EegSettings(this.eegIsShowingSettings, this.fillterSettings);
}
