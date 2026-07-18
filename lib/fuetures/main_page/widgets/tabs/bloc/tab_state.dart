part of 'tab_bloc.dart';

@immutable
sealed class TabState {
  final List<Widget> tabs; // Виджеты для TabBar
  final List<Widget> tabContents; // Содержимое вкладок
  final List<DeviceViewSession?> sessions;
  final TabController? controller;
  final int currentIndex;

  const TabState({
    required this.tabs,
    required this.tabContents,
    this.sessions = const <DeviceViewSession?>[],
    this.controller,
    this.currentIndex = 0,
  });

  /// Подключения и записи выводятся из сессий, а не лежат отдельными списками:
  /// два параллельных списка про одно и то же неизбежно разъезжаются.
  List<DeviceConnectionBloc?> get connectionBlocs => [
    for (final session in sessions) session?.connection,
  ];

  List<RecordingBloc?> get recordingBlocs => [
    for (final session in sessions) session?.recordingBloc,
  ];
}

class TabInitial extends TabState {
  const TabInitial() : super(tabs: const [], tabContents: const []);
}

class TabUpdated extends TabState {
  const TabUpdated({
    required super.tabs,
    required super.tabContents,
    required super.sessions,
    required super.controller,
    required super.currentIndex,
  });
}
