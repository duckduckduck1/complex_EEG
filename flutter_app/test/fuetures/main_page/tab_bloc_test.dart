import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/domain/recording_models.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';
import 'package:iot/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';

void main() {
  testWidgets('active recording tab is not closed', (tester) async {
    final recordingBloc = RecordingBloc(
      storage: _MemoryExperimentStorage(),
      filterFactory: const PassThroughStreamingFilterFactory(),
      idGenerator: const _FixedIdGenerator(),
    );
    final tabBloc = TabBloc(vsync: tester);
    addTearDown(tabBloc.close);
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(rootDirectory: 'memory-root'),
      ),
    );
    await tester.pump();

    tabBloc.add(
      NewTabAdded(
        newTab: const Text('recording'),
        content: const SizedBox(key: Key('recording-tab')),
        recordingBloc: recordingBloc,
      ),
    );
    tabBloc.add(
      NewTabAdded(
        newTab: const Text('idle'),
        content: const SizedBox(key: Key('idle-tab')),
      ),
    );
    await tester.pump();

    tabBloc.add(CloseTab(0));
    await tester.pump();

    expect(recordingBloc.state.status, RecordingStatus.recording);
    expect(tabBloc.state.tabs, hasLength(2));
    expect(tabBloc.state.tabContents.first.key, const Key('recording-tab'));
  });
}

class _MemoryExperimentStorage implements ExperimentStorage {
  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
  }) async {}

  @override
  Future<void> appendSamples(List<int> samples) async {}

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {}

  @override
  Future<void> close() async {}
}

class _FixedIdGenerator implements ExperimentIdGenerator {
  const _FixedIdGenerator();

  @override
  String nextId() => 'exp_tab_test';
}
