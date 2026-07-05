import 'package:flutter/material.dart';

class HalfHightLayout extends StatelessWidget {
  final Widget firstWidget;
  final Widget? secondWidget;
  final Widget? thirdWidget;
  final String firstTitle;
  final String firstMeta;
  final String? secondTitle;
  final String? secondMeta;
  final String? thirdTitle;
  final String? thirdMeta;

  const HalfHightLayout({
    super.key,
    required this.firstWidget,
    this.secondWidget,
    this.thirdWidget,
    this.firstTitle = 'Сигнал ЭЭГ',
    this.firstMeta = 'мкВ · 250 Гц',
    this.secondTitle,
    this.secondMeta,
    this.thirdTitle,
    this.thirdMeta,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPanels = <Widget>[
      if (secondWidget != null)
        _EegPanel(
          title: secondTitle ?? 'Спектр',
          meta: secondMeta ?? 'дБ',
          child: secondWidget!,
        ),
      if (thirdWidget != null)
        _EegPanel(
          title: thirdTitle ?? 'Ритмы',
          meta: thirdMeta ?? 'отн.',
          child: thirdWidget!,
        ),
    ];

    return Column(
      children: [
        Expanded(
          flex: bottomPanels.isEmpty ? 1 : 5,
          child: _EegPanel(
            title: firstTitle,
            meta: firstMeta,
            child: firstWidget,
          ),
        ),
        if (bottomPanels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Expanded(
            flex: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (bottomPanels.length == 1) {
                  return bottomPanels.first;
                }
                if (constraints.maxWidth < 680) {
                  return Column(
                    children: [
                      Expanded(child: bottomPanels[0]),
                      const SizedBox(height: 12),
                      Expanded(child: bottomPanels[1]),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: bottomPanels[0]),
                    const SizedBox(width: 12),
                    Expanded(child: bottomPanels[1]),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _EegPanel extends StatelessWidget {
  final String title;
  final String meta;
  final Widget child;

  const _EegPanel({
    required this.title,
    required this.meta,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  meta,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: ClipRect(child: child)),
          ],
        ),
      ),
    );
  }
}
