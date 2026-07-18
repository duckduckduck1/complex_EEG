import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/device_session.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/sessions_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/device_display_name.dart';
import 'package:eeg_app_max30003_stm32/features/navigation/navigation_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/presentation/recording_annotation_dialog.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc_factory.dart';
import 'package:eeg_app_max30003_stm32/features/recording/data/device_connection_fbm_transport.dart';
import 'package:eeg_app_max30003_stm32/features/recording/presentation/recording_start_dialog.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/device_eeg_tab.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/recording/recording_reservation_strip.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/tab_active_scope.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/widgets/app_selector_diolog.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/widgets/tab_bar.dart';

/// Экран без вкладок: закрыть можно и последнюю, тогда остаётся подсказка.
class _NoTabsView extends StatelessWidget {
  const _NoTabsView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tab_outlined, size: 28, color: colorScheme.outline),
          const SizedBox(height: 10),
          Text(
            'Нет открытых вкладок — добавьте устройство кнопкой «+»',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

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
    final session = await showAppSelectorDialog(context);
    if (session != null) {
      _openDeviceTab(session);
    }
  }

  void _openDeviceTab(DeviceSession session) {
    final recordingBloc = _createRecordingBloc(session);
    _tabBloc.add(
      NewTabAdded(
        newTab: Text(eegDisplayName(session.deviceId)),
        content: DeviceEegTab(
          connection: session.connection,
          recordingBloc: recordingBloc,
        ),
        connectionBloc: session.connection,
        recordingBloc: recordingBloc,
      ),
    );
  }

  RecordingBloc _createRecordingBloc(DeviceSession session) {
    return context.read<RecordingBlocFactory>().create(
      fbmTransport: DeviceConnectionFbmTransport(
        connection: session.connection,
      ),
    );
  }

  Future<void> _startRecording(RecordingBloc recordingBloc) async {
    final config = await showRecordingStartDialog(context);
    if (config != null && mounted) {
      recordingBloc.add(RecordingStartRequested(config));
    }
  }

  Future<void> _openAnnotations(RecordingBloc recordingBloc) {
    return showRecordingAnnotationDialog(
      context: context,
      recordingBloc: recordingBloc,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _tabBloc,
      child: BlocListener<NavigationCubit, NavigationState>(
        listenWhen:
            (previous, current) =>
                previous.pendingTabDeviceId != current.pendingTabDeviceId &&
                current.pendingTabDeviceId != null,
        listener: (context, state) {
          final deviceId = state.pendingTabDeviceId!;
          final session = context.read<SessionsCubit>().sessionFor(deviceId);
          if (session != null) {
            _openDeviceTab(session);
          }
          // Сбрасываем намерение в любом случае: сессии могло уже не быть
          // (устройство отключили, пока снекбар висел) — не оставляем флаг.
          context.read<NavigationCubit>().pendingTabConsumed();
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 58,
            leadingWidth: 56,
            titleSpacing: 0,
            leading: Builder(
              builder: (context) {
                return Center(
                  child: Icon(
                    Icons.check_circle,
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
            title: Row(
              children: [
                const Text('Лаборатория «Умного сна»'),
                const SizedBox(width: 16),
                Container(
                  width: 1,
                  height: 24,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: IotTabBar(tabBloc: _tabBloc),
                  ),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: BlocBuilder<TabBloc, TabState>(
                  bloc: _tabBloc,
                  builder: (context, state) {
                    final recordingBloc =
                        state.currentIndex < state.recordingBlocs.length
                            ? state.recordingBlocs[state.currentIndex]
                            : null;
                    final connectionBloc =
                        state.currentIndex < state.connectionBlocs.length
                            ? state.connectionBlocs[state.currentIndex]
                            : null;
                    return RecordingReservationStrip(
                      recordingBloc: recordingBloc,
                      onStartPressed:
                          recordingBloc == null
                              ? null
                              : () => _startRecording(recordingBloc),
                      onAnnotationsPressed:
                          recordingBloc == null
                              ? null
                              : () => _openAnnotations(recordingBloc),
                      onReconnectPressed:
                          connectionBloc == null
                              ? null
                              : () => connectionBloc.add(
                                const ManualReconnectRequested(),
                              ),
                    );
                  },
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  icon: const Icon(Icons.add, size: 24),
                  tooltip: 'Добавить вкладку устройства',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    fixedSize: const Size.square(36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _addNewTabWithApp,
                ),
              ),
            ],
          ),
          body: BlocBuilder<TabBloc, TabState>(
            builder: (context, state) {
              if (state.controller == null || state.tabContents.isEmpty) {
                return const _NoTabsView();
              }
              return IndexedStack(
                index: state.currentIndex,
                children: [
                  for (var i = 0; i < state.tabContents.length; i++)
                    TabActiveScope(
                      active: i == state.currentIndex,
                      child: state.tabContents[i],
                    ),
                ],
              );
            },
          ),
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
