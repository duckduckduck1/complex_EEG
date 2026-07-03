import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_layout/half_hight_layout.dart';

class EegLayout extends StatelessWidget {
  final bool isFiltterShowing;
  final Widget firtsWidget;
  final Widget? secondWidget;
  final Widget? thirdWidget;
  final Widget? fillterWidget;
  const EegLayout({
    super.key,
    required this.isFiltterShowing,
    required this.firtsWidget,
    this.secondWidget,
    this.thirdWidget,
    this.fillterWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (isFiltterShowing) {
      return Column(
        children: [
          Expanded(flex: 3, child: fillterWidget!),
          SizedBox(height: 20),
          Expanded(
            flex: 5,
            child: HalfHightLayout(
              firstWidget: firtsWidget,
              secondWidget: secondWidget,
              thirdWidget: thirdWidget,
            ),
          ),
        ],
      );
    }
    return HalfHightLayout(
      firstWidget: firtsWidget,
      secondWidget: secondWidget,
      thirdWidget: thirdWidget,
    );
  }
}
