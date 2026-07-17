import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_layout/half_hight_layout.dart';

class EegLayout extends StatelessWidget {
  final bool isFiltterShowing;
  final Widget firtsWidget;
  final Widget? secondWidget;
  final Widget? thirdWidget;
  final Widget? fillterWidget;
  final String firstTitle;
  final String firstMeta;
  final String? secondTitle;
  final String? secondMeta;
  final String? thirdTitle;
  final String? thirdMeta;

  const EegLayout({
    super.key,
    required this.isFiltterShowing,
    required this.firtsWidget,
    this.secondWidget,
    this.thirdWidget,
    this.fillterWidget,
    this.firstTitle = 'Сигнал ЭЭГ',
    this.firstMeta = 'мкВ · 250 Гц',
    this.secondTitle,
    this.secondMeta,
    this.thirdTitle,
    this.thirdMeta,
  });

  @override
  Widget build(BuildContext context) {
    if (isFiltterShowing && fillterWidget != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final filterMaxHeight =
              constraints.maxHeight.isFinite
                  ? (constraints.maxHeight * 0.28).clamp(72.0, 156.0)
                  : 144.0;

          return Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: filterMaxHeight),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: fillterWidget!,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: HalfHightLayout(
                  firstWidget: firtsWidget,
                  secondWidget: secondWidget,
                  thirdWidget: thirdWidget,
                  firstTitle: firstTitle,
                  firstMeta: firstMeta,
                  secondTitle: secondTitle,
                  secondMeta: secondMeta,
                  thirdTitle: thirdTitle,
                  thirdMeta: thirdMeta,
                ),
              ),
            ],
          );
        },
      );
    }
    return HalfHightLayout(
      firstWidget: firtsWidget,
      secondWidget: secondWidget,
      thirdWidget: thirdWidget,
      firstTitle: firstTitle,
      firstMeta: firstMeta,
      secondTitle: secondTitle,
      secondMeta: secondMeta,
      thirdTitle: thirdTitle,
      thirdMeta: thirdMeta,
    );
  }
}
