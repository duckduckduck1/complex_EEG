import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/exp_widget.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemWidth =
            !maxWidth.isFinite
                ? 220.0
                : maxWidth >= 720
                ? (maxWidth - 24) / 3
                : maxWidth >= 440
                ? (maxWidth - 12) / 2
                : maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _FilterControl(
              width: itemWidth,
              title: 'LP',
              enabled: _currentSettings.isLpOn,
              onEnabledChanged: (val) {
                _currentSettings.isLpOn = val;
                _updateSettings(_currentSettings);
              },
              child: FilterSlider(
                initVal: _currentSettings.lp,
                title: 'LP',
                isActive: _currentSettings.isLpOn,
                onChanged: (val) {
                  _currentSettings.lp = val;
                  _updateSettings(_currentSettings);
                },
              ),
            ),
            _FilterControl(
              width: itemWidth,
              title: 'HP',
              enabled: _currentSettings.isHpOn,
              onEnabledChanged: (val) {
                _currentSettings.isHpOn = val;
                _updateSettings(_currentSettings);
              },
              child: FilterSlider(
                initVal: _currentSettings.hp,
                title: 'HP',
                isActive: _currentSettings.isHpOn,
                onChanged: (val) {
                  _currentSettings.hp = val;
                  _updateSettings(_currentSettings);
                },
              ),
            ),
            _FilterControl(
              width: itemWidth,
              title: 'Notch',
              enabled: _currentSettings.isNotchOn,
              onEnabledChanged: (val) {
                _currentSettings.isNotchOn = val;
                _updateSettings(_currentSettings);
              },
              child: FilterSlider(
                initVal: _currentSettings.notch,
                title: 'Notch',
                isActive: _currentSettings.isNotchOn,
                onChanged: (val) {
                  _currentSettings.notch = val;
                  _updateSettings(_currentSettings);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterControl extends StatelessWidget {
  final double width;
  final String title;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final Widget child;

  const _FilterControl({
    required this.width,
    required this.title,
    required this.enabled,
    required this.onEnabledChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              enabled
                  ? colorScheme.primary.withValues(alpha: 0.08)
                  : colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                enabled
                    ? colorScheme.primary.withValues(alpha: 0.28)
                    : colorScheme.outline.withValues(alpha: 0.64),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color:
                          enabled
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color:
                            enabled
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: onEnabledChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
