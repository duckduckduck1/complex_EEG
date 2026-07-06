import 'package:flutter/material.dart';

/// Зарезервированное место под будущие кнопки управления записью эксперимента
/// (старт/стоп записи, таймер, метки, имя эксперимента).
///
/// Это НЕ рабочие контролы — только заглушка, чтобы высота уже была учтена в
/// раскладке и добавление реальных кнопок позже не сдвигало графики. Оформлена
/// подчёркнуто «неактивно» (пунктир, приглушённые цвета, бейдж «скоро»), чтобы
/// пользователь не принял её за готовую функцию.
class RecordingReservationStrip extends StatelessWidget {
  const RecordingReservationStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final muted = colorScheme.onSurfaceVariant;

    return CustomPaint(
      key: const Key('eeg-recording-reservation-strip'),
      painter: _DashedReservationPainter(
        borderColor: colorScheme.outline.withValues(alpha: 0.85),
        fillColor: colorScheme.surface.withValues(alpha: 0.45),
        radius: 16,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              Icons.fiber_manual_record,
              size: 13,
              color: muted.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Управление записью эксперимента',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SoonBadge(color: muted, borderColor: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  final Color color;
  final Color borderColor;

  const _SoonBadge({required this.color, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor.withValues(alpha: 0.7)),
      ),
      child: Text(
        'скоро',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Рисует пунктирную скруглённую рамку с лёгкой заливкой — «зарезервировано».
class _DashedReservationPainter extends CustomPainter {
  final Color borderColor;
  final Color fillColor;
  final double radius;

  const _DashedReservationPainter({
    required this.borderColor,
    required this.fillColor,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fillColor);

    final stroke =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), stroke);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedReservationPainter old) =>
      old.borderColor != borderColor ||
      old.fillColor != fillColor ||
      old.radius != radius;
}
