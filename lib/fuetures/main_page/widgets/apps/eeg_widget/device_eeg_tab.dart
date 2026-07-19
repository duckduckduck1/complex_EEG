import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/tab_active_scope.dart';

/// Вкладка живого графика одного подключённого устройства.
///
/// Ничем не владеет: и графики, и запись живут в [DeviceViewSession], которую
/// держит `TabBloc`. Вкладка — только вид, поэтому её уход с экрана (например
/// при переключении на мозаику) не трогает ни поток данных, ни запись.
///
/// `IndexedStack` держит все вкладки живыми, поэтому неактивная вкладка строила
/// бы график впустую (offstage-виджет всё равно перестраивается на каждый emit).
/// Пока вкладка неактивна, вместо [EegWidget] строится лёгкая заглушка —
/// перестройки и перерисовки графика прекращаются. **Пайплайн данных при этом
/// не трогается**: [RtEegDataBloc] в сессии продолжает считать, поэтому при
/// возврате на вкладку график сразу живой, без зависания.
class DeviceEegTab extends StatelessWidget {
  const DeviceEegTab({super.key, required this.session});

  final DeviceViewSession session;

  @override
  Widget build(BuildContext context) {
    // Активность приходит от IndexedStack по позиции вкладки, а не по устройству:
    // два таба могут смотреть на одно подключение.
    if (!TabActiveScope.of(context)) {
      return const _InactiveTabPlaceholder();
    }
    return ValueListenableBuilder<int>(
      valueListenable: session.plotSettingsRevision,
      builder:
          (context, revision, _) => EegWidget(
            key: ValueKey(revision),
            rtEegDataBloc: session.rtEegDataBloc,
          ),
    );
  }
}

/// Заглушка неактивной вкладки: график не строится и не перерисовывается.
/// Обычно не видна (вкладка offstage в `IndexedStack`) — её задача снять
/// нагрузку с перестройки графика, а не что-то показать.
class _InactiveTabPlaceholder extends StatelessWidget {
  const _InactiveTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.pause_circle_outline,
            size: 18,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            'Вкладка неактивна — график на паузе',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
