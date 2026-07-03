import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/tabs/widgets/app_selector_diolog.dart';
import 'package:iot/fuetures/main_page/widgets/tabs/widgets/tab_bar.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  late final TabBloc _tabBloc;

  @override
  void initState() {
    super.initState();
    _tabBloc = TabBloc(vsync: this);
  }

  Future<void> _addNewTabWithApp() async {
    final selectedApp = await showAppSelectorDialog(context);
    if (selectedApp != null) {
      final tabNumber = _tabBloc.state.tabs.length + 1;
      _tabBloc.add(
        NewTabAdded(newTab: Text("Tab $tabNumber"), content: selectedApp),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => _tabBloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Main Page"),
          bottom: IotTabBar(tabBloc: _tabBloc),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addNewTabWithApp,
            ),
          ],
        ),
        body: BlocBuilder<TabBloc, TabState>(
          builder: (context, state) {
            if (state.controller == null) return const Center();
            return TabBarView(
              controller: state.controller,
              children: state.tabContents, // Используем содержимое вкладок
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabBloc.close();
    super.dispose();
  }
}
