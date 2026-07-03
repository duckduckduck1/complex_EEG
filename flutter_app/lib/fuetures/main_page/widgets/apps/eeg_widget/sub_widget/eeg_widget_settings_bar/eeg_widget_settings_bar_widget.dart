import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/exp_widget.dart';

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        ShowSwitch(
          initialState: widget.initialSettings.isFilterShowing,
          title: "Filter",
          onChaged: (val) {
            setState(() {
              _currentSettings.isFilterShowing = val;
            });
            widget.onChaged(_currentSettings);
          },
        ),
        ShowSwitch(
          initialState: widget.initialSettings.isFftShowing,
          title: "FFT",
          onChaged: (val) {
            setState(() {
              _currentSettings.isFftShowing = val;
            });
            widget.onChaged(_currentSettings);
          },
        ),
        ShowSwitch(
          initialState: widget.initialSettings.isBandsShowing,
          title: "Bands",
          onChaged: (val) {
            setState(() {
              _currentSettings.isBandsShowing = val;
            });
            widget.onChaged(_currentSettings);
          },
        ),
      ],
    );
  }
}
