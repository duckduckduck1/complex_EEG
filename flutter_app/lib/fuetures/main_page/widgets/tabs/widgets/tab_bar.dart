import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';

class IotTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabBloc tabBloc;
  const IotTabBar({super.key, required this.tabBloc});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabBloc, TabState>(
      builder: (context, state) {
        if (state.controller == null) return const SizedBox();

        return TabBar(
          controller: state.controller,
          isScrollable: true,
          onTap: (index) => tabBloc.add(TabChanged(index)),
          tabs:
              state.tabs.asMap().entries.map((entry) {
                final index = entry.key;
                final tab = entry.value;
                return Tab(
                  child: Row(
                    children: [
                      tab,
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          tabBloc.add(CloseTab(index));
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
        );
      },
    );
  }
}
