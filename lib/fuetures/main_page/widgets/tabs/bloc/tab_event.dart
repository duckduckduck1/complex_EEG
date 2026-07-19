part of 'tab_bloc.dart';

@immutable
sealed class TabEvent {}

class NewTabAdded extends TabEvent {
  final Widget newTab; // Виджет для TabBar
  final Widget content; // Содержимое вкладки

  /// Живые графики и запись устройства. Владение переходит к `TabBloc`: он же
  /// закроет сессию, когда вкладку закроют.
  final DeviceViewSession? session;

  NewTabAdded({required this.newTab, required this.content, this.session});
}

class TabChanged extends TabEvent {
  final int index;

  TabChanged(this.index);
}

class CloseTab extends TabEvent {
  final int index;
  CloseTab(this.index);
}
