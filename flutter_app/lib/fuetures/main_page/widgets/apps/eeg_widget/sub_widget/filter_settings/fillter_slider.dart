import 'package:flutter/material.dart';

class FilterSlider extends StatefulWidget {
  final double initVal;
  final String title;
  final bool isActive;
  ValueChanged<double> onChanged;

  FilterSlider({
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
  Widget build(BuildContext context) {
    void onSlide(double val) {
      if (widget.isActive) {
        setState(() {
          _currentVal = val;
        });
        widget.onChanged(val);
      }
    }

    return Column(
      children: [
        Text("${widget.title} ${_currentVal.toStringAsFixed(1)} Hz"),
        Slider(
          value: widget.isActive ? _currentVal : 0,
          onChanged: onSlide,
          max: 80,
          min: 0,
          divisions: 160,
          thumbColor:
              widget.isActive ? Theme.of(context).primaryColor : Colors.grey,
        ),
      ],
    );
  }
}
