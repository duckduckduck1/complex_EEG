import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

void main() {
  late _MemoryExperimentStorage storage;
  late _FakeFbmTransport fbmTransport;
  late RecordingBloc bloc;

  setUp(() {
    storage = _MemoryExperimentStorage();
    fbmTransport = _FakeFbmTransport();
    bloc = RecordingBloc(
      storage: storage,
      filterFactory: const _OffsetFilterFactory(),
      idGenerator: const _FixedIdGenerator('exp_test_01'),
      fbmTransport: fbmTransport,
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
    expect(recording['pwm_level'], 50);
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

  test('disconnect closes segment and reconnect opens a new one', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2, 3]));
    await pumpEventQueue();

    bloc.add(const RecordingConnectionLost());
    await pumpEventQueue(times: 3);

    expect(bloc.state.status, RecordingStatus.pausedByDisconnect);
    expect(bloc.state.activeSegmentId, isNull);
    expect(bloc.state.segments.single.endSample, 3);
    expect(bloc.state.gaps.single.sampleIndex, 3);
    expect(bloc.state.gaps.single.endedAtWallClock, isNull);

    bloc.add(const RecordingSamplesReceived([99]));
    await pumpEventQueue();
    expect(storage.samples, [101, 102, 103]);

    bloc.add(const RecordingConnectionResumed());
    await pumpEventQueue(times: 3);
    bloc.add(const RecordingSamplesReceived([4, 5]));
    await pumpEventQueue();
    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 4);

    final experimentJson = storage.experimentJson!;
    final segments = experimentJson['segments']! as List<Object?>;
    final firstSegment = segments.first! as Map<String, Object?>;
    final secondSegment = segments.last! as Map<String, Object?>;
    final gaps = experimentJson['gaps']! as List<Object?>;
    final gap = gaps.single! as Map<String, Object?>;

    expect(bloc.state.status, RecordingStatus.stopped);
    expect(storage.samples, [101, 102, 103, 104, 105]);
    expect(storage.samples.contains(0), isFalse);
    expect(firstSegment['segment_id'], 'seg_1');
    expect(firstSegment['start_sample'], 0);
    expect(firstSegment['end_sample'], 3);
    expect(secondSegment['segment_id'], 'seg_2');
    expect(secondSegment['start_sample'], 3);
    expect(secondSegment['end_sample'], 5);
    expect(gap['sample_index'], 3);
    expect(gap['ended_at_wall_clock'], isNotNull);
    expect(storage.journal.map((event) => event['type']), [
      'experiment_started',
      'segment_started',
      'segment_ended',
      'connection_lost',
      'connection_resumed',
      'segment_started',
      'segment_ended',
      'recording_stopped',
    ]);
  });

  test('annotations are journaled and written to experiment json', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2, 3]));
    await pumpEventQueue();

    bloc.add(const RecordingStateLabelStarted(labelTypeId: 'sleep'));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([4, 5]));
    await pumpEventQueue();
    bloc.add(const RecordingActiveStateLabelClosed());
    await pumpEventQueue();
    bloc.add(const RecordingPointLabelAdded(labelTypeId: 'movement'));
    await pumpEventQueue();
    bloc.add(
      const RecordingExcludeIntervalAdded(
        labelTypeId: 'bad_segment',
        startSegmentSampleIndex: 1,
        endSegmentSampleIndex: 3,
      ),
    );
    await pumpEventQueue();
    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 5);

    final experimentJson = storage.experimentJson!;
    final labels = experimentJson['labels']! as List<Object?>;
    final stateLabel = labels[0]! as Map<String, Object?>;
    final pointLabel = labels[1]! as Map<String, Object?>;
    final excludeLabel = labels[2]! as Map<String, Object?>;

    expect(labels, hasLength(3));
    expect(stateLabel['kind'], 'state');
    expect(stateLabel['label_type_id'], 'sleep');
    expect(stateLabel['start_sample'], 3);
    expect(stateLabel['end_sample'], 5);
    expect(pointLabel['kind'], 'event');
    expect(pointLabel['label_type_id'], 'movement');
    expect(pointLabel['sample_index'], 4);
    expect(excludeLabel['kind'], 'exclude');
    expect(excludeLabel['start_sample'], 1);
    expect(excludeLabel['end_sample'], 3);
    expect(
      storage.journal
          .where((event) => '${event['type']}'.startsWith('annotation_'))
          .map((event) => event['type']),
      [
        'annotation_created',
        'annotation_updated',
        'annotation_created',
        'annotation_created',
      ],
    );
  });

  test('open state annotation is closed on stop', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2]));
    await pumpEventQueue();
    bloc.add(const RecordingStateLabelStarted(labelTypeId: 'sleep'));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([3, 4, 5]));
    await pumpEventQueue();

    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 5);

    final labels = storage.experimentJson!['labels']! as List<Object?>;
    final label = labels.single! as Map<String, Object?>;

    expect(bloc.state.activeDraftLabel, isNull);
    expect(label['start_sample'], 2);
    expect(label['end_sample'], 5);
    expect(label.containsKey('draft'), isFalse);
  });

  test('annotation can be deleted before final json is written', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2, 3]));
    await pumpEventQueue();
    bloc.add(const RecordingPointLabelAdded(labelTypeId: 'movement'));
    await pumpEventQueue();
    final labelId = bloc.state.labels.single.id;

    bloc.add(RecordingAnnotationDeleted(labelId));
    await pumpEventQueue();
    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 5);

    expect(bloc.state.labels, isEmpty);
    expect(storage.experimentJson!['labels'], isEmpty);
    expect(
      storage.journal.lastWhere(
        (event) => event['type'] == 'annotation_deleted',
      )['label_id'],
      labelId,
    );
  });

  test('open state annotation is closed on disconnect', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2]));
    await pumpEventQueue();
    bloc.add(const RecordingStateLabelStarted(labelTypeId: 'sleep'));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([3]));
    await pumpEventQueue();

    bloc.add(const RecordingConnectionLost());
    await pumpEventQueue(times: 5);

    final label = bloc.state.labels.single;

    expect(bloc.state.status, RecordingStatus.pausedByDisconnect);
    expect(bloc.state.activeDraftLabel, isNull);
    expect(label.isDraft, isFalse);
    expect(label.globalStartSampleIndex, 2);
    expect(label.globalEndSampleIndex, 3);
    expect(
      storage.journal
          .where((event) => event['type'] == 'annotation_updated')
          .length,
      1,
    );
  });

  test('empty state annotation is discarded without an orphan draft', () async {
    bloc.add(RecordingStartRequested(_startConfig()));
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2, 3]));
    await pumpEventQueue();

    // Открыли и тут же закрыли состояние — внутри интервала ни одного отсчёта.
    bloc.add(const RecordingStateLabelStarted(labelTypeId: 'sleep'));
    await pumpEventQueue();
    bloc.add(const RecordingActiveStateLabelClosed());
    await pumpEventQueue();

    expect(bloc.state.activeDraftLabel, isNull);
    expect(bloc.state.labels, isEmpty);
    expect(
      storage.journal
          .where((event) => '${event['type']}'.startsWith('annotation_'))
          .map((event) => event['type']),
      ['annotation_created', 'annotation_deleted'],
    );

    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 5);
    expect(storage.experimentJson!['labels'], isEmpty);
  });

  test('fbm commands call transport and write journal events', () async {
    bloc.add(RecordingStartRequested(_startConfig(pwmLevel: 20)));
    await pumpEventQueue();

    bloc.add(const FbmOnRequested());
    await pumpEventQueue();
    bloc.add(const FbmPwmChanged(60));
    await pumpEventQueue();
    bloc.add(const FbmOffRequested());
    await pumpEventQueue();

    final fbmEvents = storage.journal
        .where((event) => event['type'] == 'fbm_event')
        .toList(growable: false);

    expect(fbmTransport.commands, [
      const _FbmCommand(on: true, pwmByte: 51),
      const _FbmCommand(on: true, pwmByte: 153),
      const _FbmCommand(on: false, pwmByte: 153),
    ]);
    expect(bloc.state.fbmOn, isFalse);
    expect(bloc.state.pwmLevel, 60);
    expect(bloc.state.fbmEvents, hasLength(3));
    expect(fbmEvents.map((event) => event['on']), [true, true, false]);
    expect(fbmEvents.map((event) => event['pwm_level']), [20, 60, 60]);
    expect(fbmEvents.map((event) => event['pwm_byte']), [51, 153, 153]);
    expect(fbmEvents.map((event) => event['command_delivered']), [
      true,
      true,
      true,
    ]);
  });

  test('pwm change while fbm is off only updates next command level', () async {
    bloc.add(RecordingStartRequested(_startConfig(pwmLevel: 20)));
    await pumpEventQueue();

    bloc.add(const FbmPwmChanged(60));
    await pumpEventQueue();

    expect(bloc.state.pwmLevel, 60);
    expect(bloc.state.fbmEvents, isEmpty);
    expect(fbmTransport.commands, isEmpty);
    expect(
      storage.journal.where((event) => event['type'] == 'fbm_event'),
      isEmpty,
    );

    bloc.add(const FbmOnRequested());
    await pumpEventQueue();

    expect(fbmTransport.commands, [const _FbmCommand(on: true, pwmByte: 153)]);
    expect(bloc.state.fbmEvents.single.pwmLevel, 60);
  });

  test('fbm is ignored outside recording and auto-off on stop', () async {
    bloc.add(const FbmOnRequested());
    await pumpEventQueue();
    expect(fbmTransport.commands, isEmpty);

    bloc.add(RecordingStartRequested(_startConfig(pwmLevel: 40)));
    await pumpEventQueue();
    bloc.add(const FbmOnRequested());
    await pumpEventQueue();
    bloc.add(const RecordingSamplesReceived([1, 2]));
    await pumpEventQueue();
    bloc.add(const RecordingStopRequested());
    await pumpEventQueue(times: 5);

    final experimentJson = storage.experimentJson!;
    final fbmEvents = experimentJson['fbm_events']! as List<Object?>;

    expect(fbmTransport.commands, [
      const _FbmCommand(on: true, pwmByte: 102),
      const _FbmCommand(on: false, pwmByte: 102),
    ]);
    expect(bloc.state.status, RecordingStatus.stopped);
    expect(bloc.state.fbmOn, isFalse);
    expect(fbmEvents, hasLength(2));
    final offEvent = fbmEvents.last! as Map<String, Object?>;
    expect(offEvent['on'], isFalse);
    expect(offEvent['command_delivered'], isTrue);
    expect(offEvent['reason'], 'recording_stop');
  });

  test(
    'disconnect auto-off records undelivered command without failing',
    () async {
      bloc.add(RecordingStartRequested(_startConfig(pwmLevel: 40)));
      await pumpEventQueue();
      bloc.add(const FbmOnRequested());
      await pumpEventQueue();
      bloc.add(const RecordingSamplesReceived([1, 2]));
      await pumpEventQueue();

      fbmTransport.connected = false;
      bloc.add(const RecordingConnectionLost());
      await pumpEventQueue(times: 5);

      final fbmEvents = storage.journal
          .where((event) => event['type'] == 'fbm_event')
          .toList(growable: false);
      final autoOffEvent = fbmEvents.last;

      expect(bloc.state.status, RecordingStatus.pausedByDisconnect);
      expect(bloc.state.fbmOn, isFalse);
      expect(fbmTransport.commands, [
        const _FbmCommand(on: true, pwmByte: 102),
      ]);
      expect(autoOffEvent['on'], isFalse);
      expect(autoOffEvent['command_delivered'], isFalse);
      expect(autoOffEvent['reason'], 'connection_lost');
      expect(autoOffEvent['sample_index'], 1);
      expect(autoOffEvent['segment_sample_index'], 1);
    },
  );
}

RecordingStartConfig _startConfig({int pwmLevel = 50}) {
  return RecordingStartConfig(
    rootDirectory: 'memory-root',
    pwmLevel: pwmLevel,
    displayName: 'test recording',
    metadata: {'animal_id': 'mouse_1'},
    filters: const RecordingFilters(isLpEnabled: true),
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

class _FbmCommand {
  const _FbmCommand({required this.on, required this.pwmByte});

  final bool on;
  final int pwmByte;

  @override
  bool operator ==(Object other) {
    return other is _FbmCommand && other.on == on && other.pwmByte == pwmByte;
  }

  @override
  int get hashCode => Object.hash(on, pwmByte);
}

class _FakeFbmTransport implements FbmTransport {
  final List<_FbmCommand> commands = <_FbmCommand>[];
  bool connected = true;

  @override
  Future<bool> setLed({required bool on, required int pwmByte}) async {
    if (!connected) {
      return false;
    }
    commands.add(_FbmCommand(on: on, pwmByte: pwmByte));
    return true;
  }
}
