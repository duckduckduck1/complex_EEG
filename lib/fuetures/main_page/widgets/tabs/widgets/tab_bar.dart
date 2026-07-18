import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';

class IotTabBar extends StatelessWidget {
  final TabBloc tabBloc;
  const IotTabBar({super.key, required this.tabBloc});

  /// Закрытие вкладки по крестику.
  ///
  /// Во время записи `TabBloc` закрытие не пропустит, но молча — оператор не
  /// поймёт, почему крестик не работает. Поэтому причину объясняем здесь, а в
  /// обычном случае спрашиваем подтверждение: вкладка закрывается одним кликом,
  /// промахнуться легко.
  Future<void> _requestClose(
    BuildContext context,
    TabState state,
    int index,
  ) async {
    final recordingBloc =
        index < state.recordingBlocs.length
            ? state.recordingBlocs[index]
            : null;

    if (isRecordingBusy(recordingBloc?.state.status)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Идёт запись эксперимента — сначала остановите её, потом закрывайте',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Закрыть вкладку?'),
            content: const Text(
              'График закроется. Устройство останется подключённым — вкладку '
              'можно открыть заново.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Закрыть'),
              ),
            ],
          ),
    );

    if (confirmed ?? false) {
      tabBloc.add(CloseTab(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabBloc, TabState>(
      builder: (context, state) {
        if (state.controller == null) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        return SizedBox.expand(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: state.controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 4,
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(horizontal: 18),
              overlayColor: WidgetStatePropertyAll(
                colorScheme.primary.withValues(alpha: 0.08),
              ),
              onTap: (index) => tabBloc.add(TabChanged(index)),
              tabs:
                  state.tabs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tab = entry.value;
                    return Tab(
                      height: 44,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          tab,
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'Закрыть вкладку',
                            color: colorScheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            splashRadius: 16,
                            onPressed:
                                () => _requestClose(context, state, index),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ),
        );
      },
    );
  }
}
