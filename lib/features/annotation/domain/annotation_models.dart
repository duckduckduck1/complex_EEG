import 'package:equatable/equatable.dart';

enum AnnotationKind { state, event, exclude }

class LabelType extends Equatable {
  const LabelType({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.colorHex,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final AnnotationKind kind;
  final String displayName;
  final String colorHex;
  final bool isActive;
  final int sortOrder;

  @override
  List<Object?> get props => [
    id,
    kind,
    displayName,
    colorHex,
    isActive,
    sortOrder,
  ];
}

const defaultLabelTypes = <LabelType>[
  LabelType(
    id: 'sleep',
    kind: AnnotationKind.state,
    displayName: 'Сон',
    colorHex: '#3B82F6',
    sortOrder: 10,
  ),
  LabelType(
    id: 'rest',
    kind: AnnotationKind.state,
    displayName: 'Покой',
    colorHex: '#22C55E',
    sortOrder: 20,
  ),
  LabelType(
    id: 'eating',
    kind: AnnotationKind.state,
    displayName: 'Еда',
    colorHex: '#F59E0B',
    sortOrder: 30,
  ),
  LabelType(
    id: 'grooming',
    kind: AnnotationKind.state,
    displayName: 'Груминг',
    colorHex: '#A855F7',
    sortOrder: 40,
  ),
  LabelType(
    id: 'locomotion',
    kind: AnnotationKind.state,
    displayName: 'Локомоция',
    colorHex: '#06B6D4',
    sortOrder: 50,
  ),
  LabelType(
    id: 'custom',
    kind: AnnotationKind.state,
    displayName: 'Своё состояние',
    colorHex: '#94A3B8',
    sortOrder: 60,
  ),
  LabelType(
    id: 'startle',
    kind: AnnotationKind.event,
    displayName: 'Вздрагивание',
    colorHex: '#FB7185',
    sortOrder: 110,
  ),
  LabelType(
    id: 'movement',
    kind: AnnotationKind.event,
    displayName: 'Движение',
    colorHex: '#38BDF8',
    sortOrder: 120,
  ),
  LabelType(
    id: 'custom_event',
    kind: AnnotationKind.event,
    displayName: 'Своё событие',
    colorHex: '#CBD5E1',
    sortOrder: 130,
  ),
  LabelType(
    id: 'bad_segment',
    kind: AnnotationKind.exclude,
    displayName: 'Брак',
    colorHex: '#F43F5E',
    sortOrder: 210,
  ),
];

class AnnotationPoint extends Equatable {
  const AnnotationPoint({
    required this.segmentId,
    required this.segmentStartSample,
    required this.segmentEndSample,
    required this.segmentSampleIndex,
    required this.wallClockTime,
  });

  final String segmentId;
  final int segmentStartSample;
  final int segmentEndSample;
  final int segmentSampleIndex;
  final DateTime wallClockTime;

  int get globalSampleIndex => segmentStartSample + segmentSampleIndex;

  @override
  List<Object?> get props => [
    segmentId,
    segmentStartSample,
    segmentSampleIndex,
    wallClockTime,
    segmentEndSample,
  ];
}

class AnnotationLabel extends Equatable {
  const AnnotationLabel({
    required this.id,
    required this.kind,
    required this.labelTypeId,
    required this.segmentId,
    required this.startSegmentSampleIndex,
    required this.globalStartSampleIndex,
    required this.startedAtWallClock,
    this.endSegmentSampleIndex,
    this.globalEndSampleIndex,
    this.endedAtWallClock,
    this.note,
    this.isDraft = false,
  });

  final String id;
  final AnnotationKind kind;
  final String labelTypeId;
  final String segmentId;
  final int startSegmentSampleIndex;
  final int globalStartSampleIndex;
  final DateTime startedAtWallClock;
  final int? endSegmentSampleIndex;
  final int? globalEndSampleIndex;
  final DateTime? endedAtWallClock;
  final String? note;
  final bool isDraft;

  bool get isPoint => kind == AnnotationKind.event;

  AnnotationLabel closeAt(AnnotationPoint end) {
    return copyWith(
      endSegmentSampleIndex: end.segmentSampleIndex,
      globalEndSampleIndex: end.globalSampleIndex,
      endedAtWallClock: end.wallClockTime,
      isDraft: false,
    );
  }

  AnnotationLabel copyWith({
    int? endSegmentSampleIndex,
    int? globalEndSampleIndex,
    DateTime? endedAtWallClock,
    bool? isDraft,
  }) {
    return AnnotationLabel(
      id: id,
      kind: kind,
      labelTypeId: labelTypeId,
      segmentId: segmentId,
      startSegmentSampleIndex: startSegmentSampleIndex,
      globalStartSampleIndex: globalStartSampleIndex,
      startedAtWallClock: startedAtWallClock,
      endSegmentSampleIndex:
          endSegmentSampleIndex ?? this.endSegmentSampleIndex,
      globalEndSampleIndex: globalEndSampleIndex ?? this.globalEndSampleIndex,
      endedAtWallClock: endedAtWallClock ?? this.endedAtWallClock,
      note: note,
      isDraft: isDraft ?? this.isDraft,
    );
  }

  Map<String, Object?> toJournalJson() {
    final json = <String, Object?>{
      'label_id': id,
      'kind': kind.name,
      'label_type_id': labelTypeId,
      'segment_id': segmentId,
      if (note != null && note!.trim().isNotEmpty) 'note': note,
    };

    if (isPoint) {
      json.addAll({
        'sample_index': globalStartSampleIndex,
        'segment_sample_index': startSegmentSampleIndex,
        'global_sample_index': globalStartSampleIndex,
        'wall_clock_time': startedAtWallClock.toUtc().toIso8601String(),
      });
    } else {
      json.addAll({
        'start_sample': globalStartSampleIndex,
        if (globalEndSampleIndex != null) 'end_sample': globalEndSampleIndex,
        'start_segment_sample_index': startSegmentSampleIndex,
        if (endSegmentSampleIndex != null)
          'end_segment_sample_index': endSegmentSampleIndex,
        'started_at_wall_clock': startedAtWallClock.toUtc().toIso8601String(),
        if (endedAtWallClock != null)
          'ended_at_wall_clock': endedAtWallClock!.toUtc().toIso8601String(),
        if (isDraft) 'draft': true,
      });
    }

    return json;
  }

  Map<String, Object?> toExperimentJson() {
    if (!isPoint &&
        (endSegmentSampleIndex == null || globalEndSampleIndex == null)) {
      throw StateError('Draft interval label cannot be written to experiment');
    }
    final json = toJournalJson()..remove('draft');
    return json;
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    labelTypeId,
    segmentId,
    startSegmentSampleIndex,
    globalStartSampleIndex,
    startedAtWallClock,
    endSegmentSampleIndex,
    globalEndSampleIndex,
    endedAtWallClock,
    note,
    isDraft,
  ];
}
