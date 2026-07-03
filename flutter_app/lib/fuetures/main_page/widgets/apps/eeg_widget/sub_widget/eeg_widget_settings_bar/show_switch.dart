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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.title),
        Switch(
          value: _isOn,
          onChanged: (val) {
            setState(() {
              _isOn = val;
            });
            widget.onChaged(val);
          },
        ),
      ],
    );
  }
}
