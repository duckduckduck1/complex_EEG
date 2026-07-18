import 'package:flutter/material.dart';

/// Оборачивает график в [ClipRect] и накладывает поверх кнопку сброса
/// масштаба. Кнопка видна только когда график зазумлен (трансформация
/// контроллера отличается от единичной матрицы).
///
/// Сам зум обеспечивается `transformationConfig` внутри `LineChart` —
/// колесо мыши/тачпад масштабируют нативно; этот виджет добавляет только
/// клип и управление сбросом.
///
/// График скрыт от дерева доступности ([ExcludeSemantics]): живая осциллограмма
/// скринридеру ничего не даёт, а её узлы (подписи осей и т.п.) пересоздаются на
/// каждый кадр — до сотен раз в секунду. Windows-мост доступности такой поток
/// обновлений не переваривает и сыпет в лог `Failed to update ui::AXTree`.
/// Кнопка сброса масштаба доступной остаётся: это настоящий элемент управления.
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
        Positioned.fill(child: ClipRect(child: ExcludeSemantics(child: child))),
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
