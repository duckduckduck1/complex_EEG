part of 'tab_bloc.dart';

@immutable
sealed class TabEvent {}

class NewTabAdded extends TabEvent {
  final Widget newTab; // Виджет для TabBar
  final Widget content; // Содержимое вкладки

  NewTabAdded({required this.newTab, required this.content});
}

class TabChanged extends TabEvent {
  final int index;

  TabChanged(this.index);
}

class CloseTab extends TabEvent {
  final int index;
  CloseTab(this.index);
}
