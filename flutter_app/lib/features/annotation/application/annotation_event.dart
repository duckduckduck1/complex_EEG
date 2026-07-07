import 'package:equatable/equatable.dart';

import '../domain/annotation_models.dart';

sealed class AnnotationEvent extends Equatable {
  const AnnotationEvent();

  @override
  List<Object?> get props => [];
}

final class StateLabelStarted extends AnnotationEvent {
  const StateLabelStarted({
    required this.labelTypeId,
    required this.position,
    this.note,
  });

  final String labelTypeId;
  final AnnotationPoint position;
  final String? note;

  @override
  List<Object?> get props => [labelTypeId, position, note];
}

final class ActiveStateLabelClosed extends AnnotationEvent {
  const ActiveStateLabelClosed({required this.position});

  final AnnotationPoint position;

  @override
  List<Object?> get props => [position];
}

final class ActiveStateLabelClosedAtSegmentEnd extends AnnotationEvent {
  const ActiveStateLabelClosedAtSegmentEnd({
    required this.segmentId,
    required this.segmentEndSample,
    required this.wallClockTime,
  });

  final String segmentId;
  final int segmentEndSample;
  final DateTime wallClockTime;

  @override
  List<Object?> get props => [segmentId, segmentEndSample, wallClockTime];
}

final class PointEventLabelAdded extends AnnotationEvent {
  const PointEventLabelAdded({
    required this.labelTypeId,
    required this.position,
    this.note,
  });

  final String labelTypeId;
  final AnnotationPoint position;
  final String? note;

  @override
  List<Object?> get props => [labelTypeId, position, note];
}

final class ExcludeIntervalLabelAdded extends AnnotationEvent {
  const ExcludeIntervalLabelAdded({
    required this.labelTypeId,
    required this.start,
    required this.end,
    this.note,
  });

  final String labelTypeId;
  final AnnotationPoint start;
  final AnnotationPoint end;
  final String? note;

  @override
  List<Object?> get props => [labelTypeId, start, end, note];
}

final class AnnotationDeleted extends AnnotationEvent {
  const AnnotationDeleted(this.labelId);

  final String labelId;

  @override
  List<Object?> get props => [labelId];
}
