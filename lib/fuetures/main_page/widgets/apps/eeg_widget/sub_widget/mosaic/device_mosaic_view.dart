import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_layout.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_panel.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';

/// Все открытые устройства сеткой на одном экране.
///
/// Замена вкладкам, а не дополнение к ним: вкладки остаются лентой сверху и
/// продолжают жить, поэтому переключение режима ничего не создаёт и не рушит —
/// это два вида на один и тот же список [DeviceViewSession].
class DeviceMosaicView extends StatelessWidget {
  const DeviceMosaicView({
    super.key,
    required this.sessions,
    required this.selectedIndex,
    required this.onSelected,
    required this.onExpand,
    this.gap = 8,
  });

  final List<DeviceViewSession> sessions;

  /// Выбранная панель — это же текущая вкладка: отдельного состояния выбора
  /// нет специально, иначе оно немедленно разъехалось бы с вкладками.
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onExpand;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.all(gap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = mosaicColumns(
            deviceCount: sessions.length,
            availableWidth: constraints.maxWidth,
            availableHeight: constraints.maxHeight,
            gap: gap,
          );
          final rows = (sessions.length / columns).ceil();

          // Высоту панели задаём сами, а не отношением сторон: когда сетка
          // помещается, панели делят экран поровну; когда нет — держим
          // минимальную читаемую высоту и уезжаем в прокрутку.
          final fittingHeight =
              (constraints.maxHeight - gap * (rows - 1)) / rows;
          final panelHeight =
              fittingHeight < _minPanelHeight ? _minPanelHeight : fittingHeight;

          return GridView.builder(
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: sessions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              mainAxisExtent: panelHeight,
            ),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return DeviceMosaicPanel(
                key: ValueKey(session),
                session: session,
                title: session.title,
                isSelected: index == selectedIndex,
                onSelected: () => onSelected(index),
                onExpand: () => onExpand(index),
              );
            },
          );
        },
      ),
    );
  }
}

const _minPanelHeight = 200.0;
