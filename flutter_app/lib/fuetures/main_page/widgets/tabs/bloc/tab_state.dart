part of 'tab_bloc.dart';

@immutable
sealed class TabState {
  final List<Widget> tabs; // Виджеты для TabBar
  final List<Widget> tabContents; // Содержимое вкладок
  final TabController? controller;
  final int currentIndex;

  const TabState({
    required this.tabs,
    required this.tabContents,
    this.controller,
    this.currentIndex = 0,
  });
}

class TabInitial extends TabState {
  const TabInitial() : super(tabs: const [], tabContents: const []);
}

class TabUpdated extends TabState {
  const TabUpdated({
    required super.tabs,
    required super.tabContents,
    required super.controller,
    required super.currentIndex,
  });
}
