import 'package:flutter/material.dart';

/// Flutter code sample for [Switch].

class SwitchExample extends StatefulWidget {
  const SwitchExample({super.key});

  @override
  State<SwitchExample> createState() => _SwitchExampleState();
}

class _SwitchExampleState extends State<SwitchExample> {
  bool light = true;

  @override
  Widget build(BuildContext context) {
    // This object sets amber as the track color when the switch is selected.
    // Otherwise, it resolves to null and defers to values from the theme data.
    const WidgetStateProperty<Color?> trackColor =
        WidgetStateProperty<Color?>.fromMap(<WidgetStatesConstraint, Color>{
          WidgetState.selected: Color.fromARGB(255, 255, 255, 255),
        });
    // This object sets the track color based on two WidgetState attributes.
    // If neither state applies, it resolves to null.
    final WidgetStateProperty<Color?> overlayColor =
        WidgetStateProperty<Color?>.fromMap(<WidgetState, Color>{
          WidgetState.selected: const Color.fromARGB(
            255,
            255,
            255,
            255,
          ).withOpacity(0.54),
          WidgetState.disabled: Colors.grey.shade400,
        });

    return Switch(
      // This bool value toggles the switch.
      value: light,
      overlayColor: overlayColor,
      trackColor: trackColor,
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.black),
      onChanged: (bool value) {
        // This is called when the user toggles the switch.
        setState(() {
          light = value;
        });
      },
    );
  }
}
