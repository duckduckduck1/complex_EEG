import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/domain/recording_models.dart';

part 'tab_event.dart';
part 'tab_state.dart';

class TabBloc extends Bloc<TabEvent, TabState> {
  final TickerProvider vsync;
  late TabController _controller;

  TabBloc({required this.vsync}) : super(TabInitial()) {
    _controller = TabController(length: 0, vsync: vsync);
    on<NewTabAdded>(_onNewTabAdded);
    on<TabChanged>(_onTabChanged);
    on<CloseTab>(_onCloseTab);
  }

  void _onNewTabAdded(NewTabAdded event, Emitter<TabState> emit) {
    final newTabs = [...state.tabs, event.newTab];
    final newContents = [...state.tabContents, event.content];
    final newRecordingBlocs = [...state.recordingBlocs, event.recordingBloc];
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
        recordingBlocs: newRecordingBlocs,
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
        recordingBlocs: state.recordingBlocs,
        controller: _controller,
        currentIndex: event.index,
      ),
    );
  }

  void _onCloseTab(CloseTab event, Emitter<TabState> emit) {
    if (state.tabs.length <= 1) return; // Не закрывать последнюю вкладку
    if (event.index < 0 || event.index >= state.tabs.length) return;
    final recordingBloc =
        event.index < state.recordingBlocs.length
            ? state.recordingBlocs[event.index]
            : null;
    if (_isRecordingCloseLocked(recordingBloc)) return;

    final newTabs = List<Widget>.from(state.tabs)..removeAt(event.index);
    final newContents = List<Widget>.from(state.tabContents)
      ..removeAt(event.index);
    final newRecordingBlocs = List<RecordingBloc?>.from(state.recordingBlocs)
      ..removeAt(event.index);
    final newIndex =
        event.index < state.currentIndex
            ? state.currentIndex - 1
            : min(state.currentIndex, newTabs.length - 1);

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
        recordingBlocs: newRecordingBlocs,
        controller: _controller,
        currentIndex: newIndex,
      ),
    );
  }

  bool _isRecordingCloseLocked(RecordingBloc? recordingBloc) {
    return switch (recordingBloc?.state.status) {
      RecordingStatus.preparing ||
      RecordingStatus.recording ||
      RecordingStatus.pausedByDisconnect ||
      RecordingStatus.stopping => true,
      _ => false,
    };
  }

  @override
  Future<void> close() {
    _controller.dispose();
    return super.close();
  }
}
