import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/exp_widget.dart';

class FillterSettingsWidget extends StatefulWidget {
  final FillterSettings initSetting;
  final ValueChanged<FillterSettings> onChanged;
  const FillterSettingsWidget({
    super.key,
    required this.initSetting,
    required this.onChanged,
  });

  @override
  State<FillterSettingsWidget> createState() => _FillterSettingsWidgetState();
}

class _FillterSettingsWidgetState extends State<FillterSettingsWidget> {
  late FillterSettings _currentSettings;
  @override
  void initState() {
    _currentSettings = widget.initSetting;
    super.initState();
  }

  void _updateSettings(FillterSettings newSettings) {
    setState(() {
      _currentSettings = newSettings;
    });
    widget.onChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: FilterSlider(
                initVal: _currentSettings.lp,
                title: "lp",
                isActive: _currentSettings.isLpOn,
                onChanged: (val) {
                  _currentSettings.lp = val;
                  _updateSettings(_currentSettings);
                },
              ),
            ),
            Checkbox(
              value: _currentSettings.isLpOn,
              onChanged: (val) {
                _currentSettings.isLpOn = val!;
                _updateSettings(_currentSettings);
              },
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: FilterSlider(
                initVal: _currentSettings.hp,
                title: "hp",
                isActive: _currentSettings.isHpOn,
                onChanged: (val) {
                  _currentSettings.hp = val;
                  _updateSettings(_currentSettings);
                },
              ),
            ),
            Checkbox(
              value: _currentSettings.isHpOn,
              onChanged: (val) {
                _currentSettings.isHpOn = val!;
                _updateSettings(_currentSettings);
              },
            ),
          ],
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: FilterSlider(
                initVal: _currentSettings.notch,
                title: "notch",
                isActive: _currentSettings.isNotchOn,
                onChanged: (val) {
                  _currentSettings.notch = val;
                  _updateSettings(_currentSettings);
                },
              ),
            ),
            Checkbox(
              value: _currentSettings.isNotchOn,
              onChanged: (val) {
                _currentSettings.isNotchOn = val!;
                _updateSettings(_currentSettings);
              },
            ),
          ],
        ),
      ],
    );
  }
}
