import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
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

    _controller.dispose();
    _controller = TabController(
      length: newTabs.length,
      vsync: vsync,
      initialIndex: _controller.index,
    );

    emit(
      TabUpdated(
        tabs: newTabs,
        tabContents: newContents,
        controller: _controller,
        currentIndex: _controller.index,
      ),
    );
  }

  void _onTabChanged(TabChanged event, Emitter<TabState> emit) {
    _controller.animateTo(event.index);
    emit(
      TabUpdated(
        tabs: state.tabs,
        tabContents: state.tabContents,
        controller: _controller,
        currentIndex: event.index,
      ),
    );
  }

  void _onCloseTab(CloseTab event, Emitter<TabState> emit) {
    if (state.tabs.length <= 1) return; // Не закрывать последнюю вкладку

    final newTabs = List<Widget>.from(state.tabs)..removeAt(event.index);
    final newContents = List<Widget>.from(state.tabContents)
      ..removeAt(event.index);

    _controller.dispose();
    _controller = TabController(
      length: newTabs.length,
      vsync: vsync,
      initialIndex: min(event.index, newTabs.length - 1),
    );

    emit(
      TabUpdated(
        tabs: newTabs,
        tabContents: newContents,
        controller: _controller,
        currentIndex: _controller.index,
      ),
    );
  }

  @override
  Future<void> close() {
    try {
      _controller.dispose();
    } catch (e) {}

    return super.close();
  }
}
