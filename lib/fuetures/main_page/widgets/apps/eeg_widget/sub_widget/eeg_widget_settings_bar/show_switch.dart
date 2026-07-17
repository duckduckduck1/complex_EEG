import 'package:flutter/material.dart';

class ShowSwitch extends StatefulWidget {
  final ValueChanged<bool> onChaged;
  final String title;
  final bool initialState;
  const ShowSwitch({
    super.key,
    required this.onChaged,
    required this.title,
    required this.initialState,
  });

  @override
  State<ShowSwitch> createState() => _ShowSwitchState();
}

class _ShowSwitchState extends State<ShowSwitch> {
  late bool _isOn;

  @override
  void initState() {
    _isOn = widget.initialState;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ShowSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialState != widget.initialState) {
      _isOn = widget.initialState;
    }
  }

  void _setValue(bool value) {
    setState(() {
      _isOn = value;
    });
    widget.onChaged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final background =
        _isOn
            ? colorScheme.primary
            : colorScheme.surface.withValues(alpha: 0.72);
    final foreground =
        _isOn ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      shape: StadiumBorder(
        side: BorderSide(
          color:
              _isOn
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.72),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _setValue(!_isOn),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color:
                      _isOn
                          ? colorScheme.onPrimary
                          : colorScheme.outline.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
