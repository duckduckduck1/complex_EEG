import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';

class IotTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabBloc tabBloc;
  const IotTabBar({super.key, required this.tabBloc});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabBloc, TabState>(
      builder: (context, state) {
        if (state.controller == null) {
          return SizedBox(height: preferredSize.height);
        }

        final colorScheme = Theme.of(context).colorScheme;
        return SizedBox(
          height: preferredSize.height,
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
                            onPressed: () {
                              tabBloc.add(CloseTab(index));
                            },
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
