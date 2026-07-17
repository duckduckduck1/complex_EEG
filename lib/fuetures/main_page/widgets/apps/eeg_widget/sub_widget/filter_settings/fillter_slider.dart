import 'package:flutter/material.dart';

class FilterSlider extends StatefulWidget {
  final double initVal;
  final String title;
  final bool isActive;
  final ValueChanged<double> onChanged;

  const FilterSlider({
    super.key,
    required this.initVal,
    required this.title,
    required this.onChanged,
    required this.isActive,
  });

  @override
  State<FilterSlider> createState() => _FilterSliderState();
}

class _FilterSliderState extends State<FilterSlider> {
  late double _currentVal;

  @override
  void initState() {
    _currentVal = widget.initVal;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant FilterSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initVal != widget.initVal) {
      _currentVal = widget.initVal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = _currentVal.clamp(0.0, 80.0).toDouble();

    void onSlide(double val) {
      setState(() {
        _currentVal = val;
      });
      widget.onChanged(val);
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: widget.isActive ? 1 : 0.58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '${_currentVal.toStringAsFixed(1)} Hz',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                widget.isActive ? 'вкл' : 'выкл',
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      widget.isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              disabledThumbColor: colorScheme.onSurfaceVariant,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              onChanged: widget.isActive ? onSlide : null,
              max: 80,
              min: 0,
              divisions: 160,
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.outline.withValues(alpha: 0.58),
              thumbColor:
                  widget.isActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
