import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/domain/recording_models.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

void main() {
  late _MemoryExperimentStorage storage;
  late RecordingBloc bloc;

  setUp(() {
    storage = _MemoryExperimentStorage();
    bloc = RecordingBloc(
      storage: storage,
      filterFactory: const _OffsetFilterFactory(),
      idGenerator: const _FixedIdGenerator('exp_test_01'),
      clock: _FakeClock([
        DateTime.utc(2026, 1, 1, 10),
        DateTime.utc(2026, 1, 1, 10, 0, 5),
      ]),
    );
  });

  tearDown(() async {
    if (!bloc.isClosed) {
      await bloc.close();
    }
  });

  test('start creates experiment files and opens first segment', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();

    expect(bloc.state.status, RecordingStatus.recording);
    expect(bloc.state.experimentId, 'exp_test_01');
    expect(bloc.state.activeSegmentId, 'seg_1');
    expect(bloc.state.segments.single.startSample, 0);
    expect(storage.createdRootDirectory, 'memory-root');
    expect(storage.createdExperimentId, 'exp_test_01');
    expect(storage.journal.map((event) => event['type']), [
      'experiment_started',
      'segment_started',
    ]);
  });

  test(
    'samples are written after stateful streaming filter is applied',
    () async {
      bloc.add(RecordingStartRequested(_startConfig()));
      await pumpEventQueue();

      bloc.add(const RecordingSamplesReceived([0, 1, -1]));
      await pumpEventQueue();

      expect(storage.samples, [100, 101, 99]);
      expect(bloc.state.sampleCount, 3);
    },
  );

  test('stop writes valid experiment json without zero-fill samples', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([5, 6, 7]));
    await pumpEventQueue();

    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 4);

    final experimentJson = storage.experimentJson!;
    final recording = experimentJson['recording']! as Map<String, Object?>;
    final filters = recording['filters']! as Map<String, Object?>;
    final segments = experimentJson['segments']! as List<Object?>;
    final segment = segments.single! as Map<String, Object?>;

    expect(bloc.state.status, RecordingStatus.stopped);
    expect(storage.closed, isTrue);
    expect(storage.samples, [105, 106, 107]);
    expect(storage.samples.contains(0), isFalse);
    expect(experimentJson['experiment_id'], 'exp_test_01');
    expect(experimentJson['metadata'], {'animal_id': 'mouse_1'});
    expect(recording['sample_rate_hz'], 250);
    expect(recording['amplitude_unit'], 'microvolts');
    expect(recording['sample_encoding'], 'int32_le');
    expect(filters['lp'], {'enabled': true, 'hz': 40.0});
    expect(segment['segment_id'], 'seg_1');
    expect(segment['start_sample'], 0);
    expect(segment['end_sample'], 3);
    expect(experimentJson['labels'], isEmpty);
    expect(experimentJson['fbm_events'], isEmpty);
    expect(storage.journal.map((event) => event['type']), [
      'experiment_started',
      'segment_started',
      'segment_ended',
      'recording_stopped',
    ]);
  });

  test('close finalizes active recording package', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([11, 12]));
    await pumpEventQueue();

    await bloc.close();

    final experimentJson = storage.experimentJson!;
    final segments = experimentJson['segments']! as List<Object?>;
    final segment = segments.single! as Map<String, Object?>;

    expect(storage.closed, isTrue);
    expect(storage.samples, [111, 112]);
    expect(segment['end_sample'], 2);
    expect(storage.journal.map((event) => event['type']), [
      'experiment_started',
      'segment_started',
      'segment_ended',
      'recording_stopped',
    ]);
  });
}

RecordingStartConfig _startConfig() {
  return const RecordingStartConfig(
    rootDirectory: 'memory-root',
    displayName: 'test recording',
    metadata: {'animal_id': 'mouse_1'},
    filters: RecordingFilters(isLpEnabled: true),
  );
}

class _MemoryExperimentStorage implements ExperimentStorage {
  String? createdRootDirectory;
  String? createdExperimentId;
  final List<int> samples = <int>[];
  final List<Map<String, Object?>> journal = <Map<String, Object?>>[];
  Map<String, Object?>? experimentJson;
  int flushCount = 0;
  bool closed = false;

  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
  }) async {
    createdRootDirectory = rootDirectory;
    createdExperimentId = experimentId;
    closed = false;
  }

  @override
  Future<void> appendSamples(List<int> samples) async {
    this.samples.addAll(samples);
  }

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {
    journal.add(event);
    if (flush) flushCount++;
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {
    this.experimentJson = experimentJson;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _OffsetFilterFactory implements StreamingFilterFactory {
  const _OffsetFilterFactory();

  @override
  StreamingFilter create(RecordingFilters filters) => const _OffsetFilter(100);
}

class _OffsetFilter implements StreamingFilter {
  const _OffsetFilter(this.offset);

  final int offset;

  @override
  int filter(int sampleMicrovolts) => sampleMicrovolts + offset;
}

class _FixedIdGenerator implements ExperimentIdGenerator {
  const _FixedIdGenerator(this.id);

  final String id;

  @override
  String nextId() => id;
}

class _FakeClock implements RecordingClock {
  _FakeClock(this._values);

  final List<DateTime> _values;
  int _index = 0;

  @override
  DateTime now() {
    final value = _values[_index.clamp(0, _values.length - 1)];
    _index++;
    return value;
  }
}
