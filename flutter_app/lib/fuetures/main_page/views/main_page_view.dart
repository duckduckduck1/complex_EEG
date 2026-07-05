import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/features/devices/application/device_session.dart';
import 'package:iot/features/devices/application/sessions_cubit.dart';
import 'package:iot/features/devices/presentation/device_display_name.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/device_eeg_tab.dart';
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
    final session = await showAppSelectorDialog(context);
    if (session != null) {
      _openDeviceTab(session);
    }
  }

  void _openDeviceTab(DeviceSession session) {
    _tabBloc.add(
      NewTabAdded(
        newTab: Text(eegDisplayName(session.deviceId)),
        content: DeviceEegTab(connection: session.connection),
      ),
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
            title: const Text('Лаборатория «Умного сна»'),
            bottom: IotTabBar(tabBloc: _tabBloc),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Добавить вкладку устройства',
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _addNewTabWithApp,
                ),
              ),
            ],
          ),
          body: BlocBuilder<TabBloc, TabState>(
            builder: (context, state) {
              if (state.controller == null) return const Center();
              return IndexedStack(
                index: state.currentIndex,
                children: state.tabContents,
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
