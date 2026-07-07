import 'package:flutter_test/flutter_test.dart';
import 'package:iot/features/annotation/application/annotation_bloc.dart';
import 'package:iot/features/annotation/application/annotation_event.dart';
import 'package:iot/features/annotation/application/annotation_state.dart';
import 'package:iot/features/annotation/domain/annotation_models.dart';
import 'package:iot/features/annotation/domain/annotation_ports.dart';

void main() {
  late _MemoryAnnotationJournal journal;
  late AnnotationBloc bloc;

  setUp(() {
    journal = _MemoryAnnotationJournal();
    bloc = AnnotationBloc(
      experimentId: 'exp_annotation_test',
      journal: journal,
      idGenerator: _SequenceAnnotationIdGenerator(),
      clock: _FakeAnnotationClock(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('initial state is empty', () {
    expect(bloc.state.labels, isEmpty);
    expect(bloc.state.activeDraftLabel, isNull);
    expect(bloc.state.validationError, isNull);
  });

  test('state label starts as draft and closes as interval', () async {
    bloc.add(
      StateLabelStarted(labelTypeId: 'sleep', position: _point(local: 10)),
    );
    await pumpEventQueue();

    expect(bloc.state.activeDraftLabel, isNotNull);
    expect(bloc.state.labels.single.isDraft, isTrue);
    expect(journal.events.single['type'], 'annotation_created');

    bloc.add(ActiveStateLabelClosed(position: _point(local: 25)));
    await pumpEventQueue();

    final label = bloc.state.labels.single;
    final json = label.toJson();

    expect(bloc.state.activeDraftLabel, isNull);
    expect(label.isDraft, isFalse);
    expect(json['kind'], AnnotationKind.state.name);
    expect(json['label_type_id'], 'sleep');
    expect(json['start_sample'], 110);
    expect(json['end_sample'], 125);
    expect(json['start_segment_sample_index'], 10);
    expect(json['end_segment_sample_index'], 25);
    expect(journal.events.map((event) => event['type']), [
      'annotation_created',
      'annotation_updated',
    ]);
  });

  test('second state label is rejected while draft is open', () async {
    bloc.add(
      StateLabelStarted(labelTypeId: 'sleep', position: _point(local: 10)),
    );
    await pumpEventQueue();

    bloc.add(
      StateLabelStarted(labelTypeId: 'rest', position: _point(local: 12)),
    );
    await pumpEventQueue();

    expect(bloc.state.labels, hasLength(1));
    expect(
      bloc.state.validationError?.code,
      AnnotationValidationCode.stateAlreadyOpen,
    );
    expect(journal.events, hasLength(1));
  });

  test('point event and exclude interval are written as labels', () async {
    bloc.add(
      PointEventLabelAdded(
        labelTypeId: 'movement',
        position: _point(local: 20),
        note: 'brief artifact',
      ),
    );
    await pumpEventQueue();

    bloc.add(
      ExcludeIntervalLabelAdded(
        labelTypeId: 'bad_segment',
        start: _point(local: 30),
        end: _point(local: 45),
      ),
    );
    await pumpEventQueue();

    final pointJson = bloc.state.labels.first.toJson();
    final excludeJson = bloc.state.labels.last.toJson();

    expect(pointJson['kind'], AnnotationKind.event.name);
    expect(pointJson['sample_index'], 120);
    expect(pointJson['segment_sample_index'], 20);
    expect(pointJson['note'], 'brief artifact');
    expect(excludeJson['kind'], AnnotationKind.exclude.name);
    expect(excludeJson['start_sample'], 130);
    expect(excludeJson['end_sample'], 145);
    expect(journal.events.map((event) => event['type']), [
      'annotation_created',
      'annotation_created',
    ]);
  });

  test('interval cannot cross segment boundary', () async {
    bloc.add(
      ExcludeIntervalLabelAdded(
        labelTypeId: 'bad_segment',
        start: _point(local: 10, segmentEndSample: 140),
        end: _point(local: 45, segmentEndSample: 140),
      ),
    );
    await pumpEventQueue();

    expect(bloc.state.labels, isEmpty);
    expect(
      bloc.state.validationError?.code,
      AnnotationValidationCode.intervalOutsideSegment,
    );
    expect(journal.events, isEmpty);
  });

  test('open state closes at segment end', () async {
    bloc.add(
      StateLabelStarted(labelTypeId: 'sleep', position: _point(local: 10)),
    );
    await pumpEventQueue();

    bloc.add(
      ActiveStateLabelClosedAtSegmentEnd(
        segmentId: 'seg_1',
        segmentEndSample: 150,
        wallClockTime: DateTime.utc(2026, 1, 1, 10, 0, 20),
      ),
    );
    await pumpEventQueue();

    final json = bloc.state.labels.single.toJson();

    expect(bloc.state.activeDraftLabel, isNull);
    expect(json['end_sample'], 150);
    expect(json['end_segment_sample_index'], 50);
  });

  test('delete removes label and writes journal event', () async {
    bloc.add(
      PointEventLabelAdded(
        labelTypeId: 'movement',
        position: _point(local: 20),
      ),
    );
    await pumpEventQueue();
    final labelId = bloc.state.labels.single.id;

    bloc.add(AnnotationDeleted(labelId));
    await pumpEventQueue();

    expect(bloc.state.labels, isEmpty);
    expect(journal.events.last['type'], 'annotation_deleted');
    expect(journal.events.last['experiment_id'], 'exp_annotation_test');
    expect(journal.events.last['label_id'], labelId);
    expect(journal.events.last['timestamp'], '2026-01-01T11:00:00.000Z');
  });
}

AnnotationPoint _point({
  required int local,
  int segmentStartSample = 100,
  int? segmentEndSample = 200,
}) {
  return AnnotationPoint(
    segmentId: 'seg_1',
    segmentStartSample: segmentStartSample,
    segmentSampleIndex: local,
    wallClockTime: DateTime.utc(2026, 1, 1, 10, 0, local),
    segmentEndSample: segmentEndSample,
  );
}

class _MemoryAnnotationJournal implements AnnotationJournal {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  @override
  Future<void> appendAnnotation(
    Map<String, Object?> event, {
    bool flush = true,
  }) async {
    events.add(event);
  }
}

class _SequenceAnnotationIdGenerator implements AnnotationIdGenerator {
  int _next = 1;

  @override
  String nextId() => 'label_${_next++}';
}

class _FakeAnnotationClock implements AnnotationClock {
  @override
  DateTime now() => DateTime.utc(2026, 1, 1, 11);
}
