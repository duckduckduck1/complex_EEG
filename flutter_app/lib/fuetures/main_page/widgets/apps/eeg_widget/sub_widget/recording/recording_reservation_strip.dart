import 'package:flutter/material.dart';

class RecordingReservationStrip extends StatelessWidget {
  const RecordingReservationStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      key: const Key('eeg-recording-reservation-strip'),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.92)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: compact ? 10 : 16,
              runSpacing: 8,
              children: [
                _PlaceholderPill(width: compact ? 112 : 170),
                _PlaceholderPill(width: compact ? 96 : 150),
                _StatusToken(
                  icon: Icons.fiber_manual_record,
                  label: 'Запись',
                  color: colorScheme.onSurfaceVariant,
                ),
                _StatusToken(
                  icon: Icons.timer_outlined,
                  label: '00:00',
                  color: colorScheme.onSurfaceVariant,
                ),
                _StatusToken(
                  icon: Icons.flag,
                  label: 'Метки',
                  color: colorScheme.primary,
                ),
                Text(
                  'Эксперимент',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!compact) ...[
                  _PlaceholderPill(width: 170),
                  _PlaceholderPill(width: 150),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusToken extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusToken({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(label, style: textStyle),
      ],
    );
  }
}

class _PlaceholderPill extends StatelessWidget {
  final double width;

  const _PlaceholderPill({required this.width});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: 22,
      decoration: BoxDecoration(
        color: colorScheme.outline.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
