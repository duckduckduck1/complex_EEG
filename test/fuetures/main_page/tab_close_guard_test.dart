import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/widgets/tab_bar.dart';

void main() {
  Widget wrap(TabBloc tabBloc) {
    return MaterialApp(
      home: BlocProvider<TabBloc>.value(
        value: tabBloc,
        child: Scaffold(
          appBar: AppBar(
            title: SizedBox(height: 46, child: IotTabBar(tabBloc: tabBloc)),
          ),
        ),
      ),
    );
  }

  RecordingBloc createRecordingBloc() {
    return RecordingBloc(
      storage: _MemoryExperimentStorage(),
      filterFactory: const PassThroughStreamingFilterFactory(),
      idGenerator: const _FixedIdGenerator(),
      fbmTransport: const _FakeFbmTransport(),
    );
  }

  testWidgets('во время записи крестик объясняет, почему нельзя закрыть', (
    tester,
  ) async {
    final recordingBloc = createRecordingBloc();
    final tabBloc = TabBloc(vsync: tester);
    addTearDown(tabBloc.close);
    addTearDown(() async {
      if (!recordingBloc.isClosed) await recordingBloc.close();
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();

    tabBloc.add(
      NewTabAdded(
        newTab: const Text('Мышь 1'),
        content: const SizedBox(),
        recordingBloc: recordingBloc,
      ),
    );
    await tester.pumpWidget(wrap(tabBloc));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.textContaining('Идёт запись эксперимента'), findsOneWidget);
    expect(tabBloc.state.tabs, hasLength(1), reason: 'вкладка не закрылась');
  });

  testWidgets('обычная вкладка закрывается только после подтверждения', (
    tester,
  ) async {
    final tabBloc = TabBloc(vsync: tester);
    addTearDown(tabBloc.close);

    tabBloc.add(
      NewTabAdded(newTab: const Text('первая'), content: const SizedBox()),
    );
    tabBloc.add(
      NewTabAdded(newTab: const Text('вторая'), content: const SizedBox()),
    );
    await tester.pumpWidget(wrap(tabBloc));
    await tester.pump();
    expect(tabBloc.state.tabs, hasLength(2));

    // Отмена — вкладка остаётся.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Закрыть вкладку?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tabBloc.state.tabs, hasLength(2));

    // Подтверждение — закрывается.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(tabBloc.state.tabs, hasLength(1));
  });
}

class _MemoryExperimentStorage implements ExperimentStorage {
  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
    required String folderName,
  }) async {}

  @override
  Future<void> appendSamples({
    required List<int> filtered,
    required List<int> raw,
  }) async {}

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> writeReadme(String text) async {}

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {}

  @override
  Future<void> close() async {}
}

class _FixedIdGenerator implements ExperimentIdGenerator {
  const _FixedIdGenerator();

  @override
  String nextId() => '01KXTF74CQSD65FWE0S2DF1WWZ';
}

class _FakeFbmTransport implements FbmTransport {
  const _FakeFbmTransport();

  @override
  Future<bool> setLed({required bool on, required int pwmByte}) async => true;
}
