import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/features/devices/application/device_session.dart';
import 'package:iot/features/devices/application/sessions_cubit.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_event.dart';
import 'package:iot/features/devices/presentation/blocs/device_connection_state.dart';
import 'package:iot/features/devices/presentation/blocs/device_discovery_bloc.dart';
import 'package:iot/features/devices/presentation/blocs/device_discovery_event.dart';
import 'package:iot/features/devices/presentation/blocs/device_discovery_state.dart';
import 'package:iot/features/devices/presentation/device_display_name.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';

/// Имя модели стенда — фильтр поиска по рекламируемому имени
/// (docs/reference/device_packet.md; имя — фильтр, не доверенный
/// идентификатор). Адаптер дополнительно матчит по сервису 0xFFE0.
const String _jdyModelName = 'JDY-16';

/// Экран поиска и подключения к BLE-устройствам.
///
/// Поиск ([DeviceDiscoveryBloc]) создаётся один раз и живёт весь жизненный
/// цикл экрана. Подключение к конкретному устройству управляется общим
/// [SessionsCubit] (docs/flutter_app/architecture.md, «Изоляция нескольких
/// устройств») — сразу несколько устройств могут иметь независимые активные
/// сессии одновременно. Этот экран не показывает график сигнала: показ
/// графика — отдельное действие на экране «Главная» (вкладки).
class BlePageView extends StatefulWidget {
  /// [adapter] позволяет подставить fake-реализацию в тестах; в production
  /// экран берёт общий [BleAdapter] из [context] (`RepositoryProvider`,
  /// поднятый в `main_app.dart`).
  const BlePageView({super.key, BleAdapter? adapter}) : _adapter = adapter;

  final BleAdapter? _adapter;

  @override
  State<BlePageView> createState() => _BlePageViewState();
}

class _BlePageViewState extends State<BlePageView> {
  late final DeviceDiscoveryBloc _discoveryBloc;

  @override
  void initState() {
    super.initState();
    final adapter = widget._adapter ?? context.read<BleAdapter>();
    _discoveryBloc = DeviceDiscoveryBloc(adapter: adapter);
  }

  @override
  void dispose() {
    _discoveryBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NavigationCubit, NavigationState>(
      listenWhen:
          (previous, current) =>
              !previous.autoStartDiscoveryRequested &&
              current.autoStartDiscoveryRequested,
      listener: (context, state) {
        _discoveryBloc.add(const DiscoveryStarted(namePrefix: _jdyModelName));
        context.read<NavigationCubit>().discoveryAutoStartConsumed();
      },
      child: Scaffold(
        appBar: AppBar(centerTitle: true, title: const Text('Поиск устройств')),
        body: BlocProvider.value(
          value: _discoveryBloc,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiscoveryControls(discoveryBloc: _discoveryBloc),
              const Divider(height: 1),
              Expanded(
                child: BlocBuilder<DeviceDiscoveryBloc, DeviceDiscoveryState>(
                  builder: (context, state) {
                    if (state.status == DiscoveryStatus.failed) {
                      return _ErrorBanner(
                        message:
                            state.failure?.message ??
                            'Ошибка поиска устройств.',
                      );
                    }
                    if (state.devices.isEmpty) {
                      return const Center(child: Text('Устройства не найдены'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: state.devices.length,
                      itemBuilder: (context, index) {
                        final device = state.devices[index];
                        return _DeviceCard(device: device);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryControls extends StatelessWidget {
  const _DiscoveryControls({required this.discoveryBloc});

  final DeviceDiscoveryBloc discoveryBloc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: BlocBuilder<DeviceDiscoveryBloc, DeviceDiscoveryState>(
        builder: (context, state) {
          final isScanning = state.status == DiscoveryStatus.scanning;
          return Row(
            children: [
              ElevatedButton(
                onPressed: () {
                  if (isScanning) {
                    discoveryBloc.add(const DiscoveryStopped());
                  } else {
                    discoveryBloc.add(
                      const DiscoveryStarted(namePrefix: _jdyModelName),
                    );
                  }
                },
                child: Text(isScanning ? 'Стоп' : 'Искать'),
              ),
              const SizedBox(width: 12),
              if (isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Карточка одного найденного устройства.
///
/// Без активной сессии тап подключает устройство ([SessionsCubit.openSession]).
/// С активной сессией карточка показывает статус подключения из её
/// [DeviceConnectionBloc] и позволяет переподключиться/отключиться — повторный
/// тап по самой карточке ничего не делает (сессия уже открыта).
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final session = context.select<SessionsCubit, DeviceSession?>(
      (cubit) => cubit.sessionFor(device.id),
    );

    if (session == null) {
      return Card(
        child: InkWell(
          onTap: () => context.read<SessionsCubit>().openSession(device),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_disabled, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eegDisplayName(device.id),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Не подключено',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      // Признак «живости» персистентного списка: RSSI есть
                      // только у устройств, подтверждённых текущим поиском
                      // (требование Richard от 2026-07-05 — отмена прежнего
                      // решения «RSSI на карточке лишний»). Карточка с
                      // сессией этой строки не имеет: подключённое устройство
                      // не рекламирует себя, «не найдено» было бы ложной
                      // тревогой.
                      if (device.rssi != null)
                        Text(
                          'RSSI: ${device.rssi} дБм',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Text(
                          'Не найдено в последнем поиске',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).disabledColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return BlocProvider.value(
      value: session.connection,
      child: BlocConsumer<DeviceConnectionBloc, DeviceConnectionState>(
        // Ровно один раз на каждый переход в connected (в том числе после
        // переподключения) — не срабатывает повторно на ребилдах карточки.
        listenWhen:
            (previous, current) =>
                previous.status != DeviceConnectionStatus.connected &&
                current.status == DeviceConnectionStatus.connected,
        listener: (context, state) {
          // Снекбар живёт дольше, чем контекст карточки может оставаться
          // смонтированным, — берём кубит заранее и захватываем в замыкание.
          final navigationCubit = context.read<NavigationCubit>();
          final deviceId = device.id;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              // Без persist (по умолчанию включается при наличии action):
              // иначе снекбар первого устройства висел бы вечно и заслонял
              // очередь уведомлений следующих подключённых устройств.
              persist: false,
              content: Text(
                'Устройство ${eegDisplayName(deviceId)} подключено',
              ),
              action: SnackBarAction(
                label: 'Открыть график',
                onPressed: () {
                  navigationCubit
                    ..setPendingTab(deviceId)
                    ..selectSection(0);
                },
              ),
            ),
          );
        },
        builder: (context, state) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    state.status == DeviceConnectionStatus.connected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth,
                    color:
                        state.status == DeviceConnectionStatus.connected
                            ? Colors.blue
                            : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eegDisplayName(device.id),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _statusText(state),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ..._actions(context, state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _actions(BuildContext context, DeviceConnectionState state) {
    final canReconnect =
        state.status == DeviceConnectionStatus.lost ||
        state.status == DeviceConnectionStatus.failed;
    if (canReconnect) {
      return [
        ElevatedButton(
          onPressed:
              () => context.read<DeviceConnectionBloc>().add(
                const ManualReconnectRequested(),
              ),
          child: const Text('Переподключиться'),
        ),
      ];
    }
    if (state.status == DeviceConnectionStatus.connected) {
      return [
        OutlinedButton(
          onPressed:
              () => context.read<SessionsCubit>().closeSession(device.id),
          child: const Text('Отключить'),
        ),
      ];
    }
    return const [];
  }

  String _statusText(DeviceConnectionState state) {
    if (state.status == DeviceConnectionStatus.failed &&
        state.failure != null) {
      return state.failure!.message;
    }
    switch (state.status) {
      case DeviceConnectionStatus.disconnected:
        return 'Не подключено';
      case DeviceConnectionStatus.connecting:
        return 'Подключение…';
      case DeviceConnectionStatus.connected:
        return 'Подключено';
      case DeviceConnectionStatus.lost:
        return 'Связь потеряна';
      case DeviceConnectionStatus.reconnectingManually:
        return 'Переподключение…';
      case DeviceConnectionStatus.failed:
        return 'Не удалось подключиться';
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
