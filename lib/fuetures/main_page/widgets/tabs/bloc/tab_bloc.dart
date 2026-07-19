import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';

part 'tab_event.dart';
part 'tab_state.dart';

/// Вкладки устройств и владелец их [DeviceViewSession].
///
/// Сессию заводит тот, кто открывает вкладку, а закрывает всегда этот bloc —
/// на закрытии вкладки и на своём собственном закрытии. Виду сессию во владение
/// не отдаём специально: вид может уйти с экрана (переключение на мозаику,
/// offstage-вкладка), а запись при этом обязана продолжаться.
class TabBloc extends Bloc<TabEvent, TabState> {
  final TickerProvider vsync;
  late TabController _controller;

  TabBloc({required this.vsync}) : super(const TabInitial()) {
    _controller = TabController(length: 0, vsync: vsync);
    on<NewTabAdded>(_onNewTabAdded);
    on<TabChanged>(_onTabChanged);
    on<CloseTab>(_onCloseTab);
  }

  void _onNewTabAdded(NewTabAdded event, Emitter<TabState> emit) {
    final newTabs = [...state.tabs, event.newTab];
    final newContents = [...state.tabContents, event.content];
    final newSessions = [...state.sessions, event.session];
    final newIndex = newTabs.length - 1;

    _controller.dispose();
    _controller = TabController(
      length: newTabs.length,
      vsync: vsync,
      initialIndex: newIndex,
    );

    emit(
      TabUpdated(
        tabs: newTabs,
        tabContents: newContents,
        sessions: newSessions,
        controller: _controller,
        currentIndex: newIndex,
      ),
    );
  }

  void _onTabChanged(TabChanged event, Emitter<TabState> emit) {
    if (event.index < 0 || event.index >= state.tabs.length) {
      return;
    }
    _controller.animateTo(event.index);
    emit(
      TabUpdated(
        tabs: state.tabs,
        tabContents: state.tabContents,
        sessions: state.sessions,
        controller: _controller,
        currentIndex: event.index,
      ),
    );
  }

  void _onCloseTab(CloseTab event, Emitter<TabState> emit) {
    if (event.index < 0 || event.index >= state.tabs.length) return;
    final session =
        event.index < state.sessions.length
            ? state.sessions[event.index]
            : null;
    if (_isRecordingCloseLocked(session?.recordingBloc)) return;

    final newTabs = List<Widget>.from(state.tabs)..removeAt(event.index);
    final newContents = List<Widget>.from(state.tabContents)
      ..removeAt(event.index);
    final newSessions = List<DeviceViewSession?>.from(state.sessions)
      ..removeAt(event.index);
    // Закрыть можно и последнюю вкладку — тогда остаётся пустой экран.
    final newIndex =
        newTabs.isEmpty
            ? 0
            : (event.index < state.currentIndex
                ? state.currentIndex - 1
                : min(state.currentIndex, newTabs.length - 1));

    _controller.dispose();
    _controller = TabController(
      length: newTabs.length,
      vsync: vsync,
      initialIndex: newIndex,
    );

    emit(
      TabUpdated(
        tabs: newTabs,
        tabContents: newContents,
        sessions: newSessions,
        controller: _controller,
        currentIndex: newIndex,
      ),
    );

    // Закрываем после emit: вид уже перестроился без этой вкладки и не успеет
    // обратиться к закрытым bloc'ам.
    unawaited(session?.dispose());
  }

  bool _isRecordingCloseLocked(RecordingBloc? recordingBloc) =>
      isRecordingBusy(recordingBloc?.state.status);

  @override
  Future<void> close() async {
    _controller.dispose();
    for (final session in state.sessions) {
      await session?.dispose();
    }
    return super.close();
  }
}
