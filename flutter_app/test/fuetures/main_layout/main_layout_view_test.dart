import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/devices/application/sessions_cubit.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/devices/domain/ble_device.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';
import 'package:iot/fuetures/main_layout/views/main_layout_view.dart';

class _FakeAdapter implements BleAdapter {
  @override
  Stream<DiscoveredDevice> scan({String? namePrefix}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Future<BleConnection> connect(BleDeviceId id) async =>
      throw UnimplementedError();
}

void main() {
  Widget buildApp(NavigationCubit cubit) {
    final adapter = _FakeAdapter();
    return MaterialApp(
      home: RepositoryProvider<BleAdapter>(
        create: (_) => adapter,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<NavigationCubit>.value(value: cubit),
            BlocProvider<SessionsCubit>(
              create: (_) => SessionsCubit(adapter: adapter),
            ),
          ],
          child: const MainLayout(),
        ),
      ),
    );
  }

  testWidgets('selectSection(1) показывает вторую страницу IndexedStack', (
    tester,
  ) async {
    final cubit = NavigationCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(buildApp(cubit));

    IndexedStack findStack() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack));

    expect(findStack().index, 0);

    cubit.selectSection(1);
    await tester.pump();

    expect(findStack().index, 1);
  });

  testWidgets('NavigationRail тоже переключает раздел через кубит', (
    tester,
  ) async {
    final cubit = NavigationCubit();
    addTearDown(cubit.close);

    // Широкий экран — показывает NavigationRail.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(cubit));

    // NavigationRail скрывает подписи (labelType: none), поэтому тапаем по
    // иконке раздела, а не по тексту.
    await tester.tap(find.byIcon(Icons.devices));
    await tester.pump();

    expect(cubit.state.sectionIndex, 1);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
  });
}
