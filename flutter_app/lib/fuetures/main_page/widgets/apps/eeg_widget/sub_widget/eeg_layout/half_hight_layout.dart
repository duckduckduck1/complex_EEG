import 'package:flutter/material.dart';

class HalfHightLayout extends StatelessWidget {
  final Widget firstWidget;
  final Widget? secondWidget;
  final Widget? thirdWidget;
  const HalfHightLayout({
    super.key,
    required this.firstWidget,
    this.secondWidget,
    this.thirdWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: firstWidget),
        secondWidget == null && thirdWidget == null
            ? const SizedBox.shrink()
            : Expanded(
              child: Row(
                children: [
                  if (secondWidget != null)
                    Expanded(
                      flex: thirdWidget == null ? 2 : 1,
                      child: secondWidget!,
                    ),
                  if (thirdWidget != null) Expanded(child: thirdWidget!),
                ],
              ),
            ),
      ],
    );
  }
}
