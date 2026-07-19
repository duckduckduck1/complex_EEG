import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/exp_widget.dart';

class EegWidgetSettingsBar extends StatefulWidget {
  final EegIsShowingSettings initialSettings;
  final ValueChanged<EegIsShowingSettings> onChaged;
  const EegWidgetSettingsBar({
    super.key,
    required this.initialSettings,
    required this.onChaged,
  });

  @override
  State<EegWidgetSettingsBar> createState() => _EegWidgetSettingsBarState();
}

class _EegWidgetSettingsBarState extends State<EegWidgetSettingsBar> {
  late EegIsShowingSettings _currentSettings;
  @override
  void initState() {
    _currentSettings = widget.initialSettings;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        ShowSwitch(
          initialState: widget.initialSettings.isFilterShowing,
          title: 'Фильтр',
          onChaged: (val) {
            setState(() {
              _currentSettings = _currentSettings.copyWith(
                isFilterShowing: val,
              );
            });
            widget.onChaged(_currentSettings);
          },
        ),
        ShowSwitch(
          initialState: widget.initialSettings.isFftShowing,
          title: 'Спектр',
          onChaged: (val) {
            setState(() {
              _currentSettings = _currentSettings.copyWith(isFftShowing: val);
            });
            widget.onChaged(_currentSettings);
          },
        ),
        ShowSwitch(
          initialState: widget.initialSettings.isBandsShowing,
          title: 'Ритмы',
          onChaged: (val) {
            setState(() {
              _currentSettings = _currentSettings.copyWith(isBandsShowing: val);
            });
            widget.onChaged(_currentSettings);
          },
        ),
      ],
    );
  }
}
