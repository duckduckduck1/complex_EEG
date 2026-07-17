import 'package:flutter/material.dart';

/// Оборачивает график в [ClipRect] и накладывает поверх кнопку сброса
/// масштаба. Кнопка видна только когда график зазумлен (трансформация
/// контроллера отличается от единичной матрицы).
///
/// Сам зум обеспечивается `transformationConfig` внутри `LineChart` —
/// колесо мыши/тачпад масштабируют нативно; этот виджет добавляет только
/// клип и управление сбросом.
class ZoomableChart extends StatelessWidget {
  final TransformationController transformController;
  final ColorScheme colorScheme;
  final Widget child;

  const ZoomableChart({
    super.key,
    required this.transformController,
    required this.colorScheme,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: ClipRect(child: child)),
        Positioned(
          top: 4,
          right: 4,
          child: AnimatedBuilder(
            animation: transformController,
            builder: (context, _) {
              final isZoomed = transformController.value != Matrix4.identity();
              return IgnorePointer(
                ignoring: !isZoomed,
                child: AnimatedOpacity(
                  opacity: isZoomed ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Material(
                    color: colorScheme.surface.withValues(alpha: 0.82),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: 'Сбросить масштаб',
                      icon: Icon(
                        Icons.zoom_out_map,
                        color: colorScheme.onSurface,
                      ),
                      onPressed: () {
                        transformController.value = Matrix4.identity();
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
