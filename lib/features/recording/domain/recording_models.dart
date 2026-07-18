import 'package:equatable/equatable.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';

enum RecordingStatus {
  idle,
  preparing,
  recording,
  pausedByDisconnect,
  stopping,
  stopped,
  failed,
}

class RecordingFilters extends Equatable {
  const RecordingFilters({
    this.lpHz = 40,
    this.hpHz = 0.5,
    this.notchHz = 50,
    this.isLpEnabled = false,
    this.isHpEnabled = false,
    this.isNotchEnabled = false,
  });

  final double lpHz;
  final double hpHz;
  final double notchHz;
  final bool isLpEnabled;
  final bool isHpEnabled;
  final bool isNotchEnabled;

  Map<String, Object> toJson() => {
    'lp': {'enabled': isLpEnabled, 'hz': lpHz},
    'hp': {'enabled': isHpEnabled, 'hz': hpHz},
    'notch': {'enabled': isNotchEnabled, 'hz': notchHz},
  };

  @override
  List<Object?> get props => [
    lpHz,
    hpHz,
    notchHz,
    isLpEnabled,
    isHpEnabled,
    isNotchEnabled,
  ];
}

class RecordingStartConfig extends Equatable {
  const RecordingStartConfig({
    required this.rootDirectory,
    required this.pwmLevel,
    required this.displayName,
    this.metadata = const <String, Object?>{},
    this.filters = const RecordingFilters(),
    this.sampleRateHz = 250,
  }) : assert(pwmLevel >= 1 && pwmLevel <= 99);

  final String rootDirectory;
  final int pwmLevel;

  /// Название эксперимента: им же называется папка на диске («Мышь 1»).
  final String displayName;
  final Map<String, Object?> metadata;
  final RecordingFilters filters;
  final int sampleRateHz;

  @override
  List<Object?> get props => [
    rootDirectory,
    pwmLevel,
    displayName,
    metadata,
    filters,
    sampleRateHz,
  ];
}

class RecordingFbmEvent extends Equatable {
  const RecordingFbmEvent({
    required this.segmentId,
    required this.segmentSampleIndex,
    required this.globalSampleIndex,
    required this.wallClockTime,
    required this.isOn,
    required this.pwmLevel,
    required this.pwmByte,
    required this.commandDelivered,
    this.reason,
  });

  final String segmentId;
  final int segmentSampleIndex;
  final int globalSampleIndex;
  final DateTime wallClockTime;
  final bool isOn;
  final int pwmLevel;
  final int pwmByte;
  final bool commandDelivered;
  final String? reason;

  Map<String, Object?> toJson() => {
    'segment_id': segmentId,
    'sample_index': globalSampleIndex,
    'segment_sample_index': segmentSampleIndex,
    'global_sample_index': globalSampleIndex,
    'wall_clock_time': wallClockTime.toUtc().toIso8601String(),
    'on': isOn,
    'pwm_level': pwmLevel,
    'pwm_byte': pwmByte,
    'command_delivered': commandDelivered,
    if (reason != null) 'reason': reason,
  };

  @override
  List<Object?> get props => [
    segmentId,
    segmentSampleIndex,
    globalSampleIndex,
    wallClockTime,
    isOn,
    pwmLevel,
    pwmByte,
    commandDelivered,
    reason,
  ];
}

class RecordingSegment extends Equatable {
  const RecordingSegment({
    required this.segmentId,
    required this.startSample,
    this.endSample,
    required this.startedAtWallClock,
    this.endedAtWallClock,
  });

  final String segmentId;
  final int startSample;
  final int? endSample;
  final DateTime startedAtWallClock;
  final DateTime? endedAtWallClock;

  bool get isClosed => endSample != null;

  RecordingSegment close({
    required int endSample,
    required DateTime endedAtWallClock,
  }) {
    return RecordingSegment(
      segmentId: segmentId,
      startSample: startSample,
      endSample: endSample,
      startedAtWallClock: startedAtWallClock,
      endedAtWallClock: endedAtWallClock,
    );
  }

  Map<String, Object?> toJson() => {
    'segment_id': segmentId,
    'start_sample': startSample,
    'end_sample': endSample,
    'started_at_wall_clock': startedAtWallClock.toUtc().toIso8601String(),
    if (endedAtWallClock != null)
      'ended_at_wall_clock': endedAtWallClock!.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    segmentId,
    startSample,
    endSample,
    startedAtWallClock,
    endedAtWallClock,
  ];
}

class RecordingGap extends Equatable {
  const RecordingGap({
    required this.startedAtWallClock,
    this.endedAtWallClock,
    required this.sampleIndex,
  });

  final DateTime startedAtWallClock;
  final DateTime? endedAtWallClock;
  final int sampleIndex;

  Map<String, Object?> toJson() => {
    'started_at_wall_clock': startedAtWallClock.toUtc().toIso8601String(),
    if (endedAtWallClock != null)
      'ended_at_wall_clock': endedAtWallClock!.toUtc().toIso8601String(),
    'sample_index': sampleIndex,
  };

  @override
  List<Object?> get props => [
    startedAtWallClock,
    endedAtWallClock,
    sampleIndex,
  ];
}

class RecordingFailure extends Equatable {
  const RecordingFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class RecordingState extends Equatable {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.experimentId,
    this.displayName,
    this.sampleCount = 0,
    this.activeSegmentId,
    this.segments = const <RecordingSegment>[],
    this.gaps = const <RecordingGap>[],
    this.labels = const <AnnotationLabel>[],
    this.activeDraftLabel,
    this.pwmLevel,
    this.fbmOn = false,
    this.fbmEvents = const <RecordingFbmEvent>[],
    this.lastError,
  });

  final RecordingStatus status;
  final String? experimentId;
  final String? displayName;
  final int sampleCount;
  final String? activeSegmentId;
  final List<RecordingSegment> segments;
  final List<RecordingGap> gaps;
  final List<AnnotationLabel> labels;
  final AnnotationLabel? activeDraftLabel;
  final int? pwmLevel;
  final bool fbmOn;
  final List<RecordingFbmEvent> fbmEvents;
  final RecordingFailure? lastError;

  static const _unset = Object();

  RecordingState copyWith({
    RecordingStatus? status,
    Object? experimentId = _unset,
    Object? displayName = _unset,
    int? sampleCount,
    Object? activeSegmentId = _unset,
    List<RecordingSegment>? segments,
    List<RecordingGap>? gaps,
    List<AnnotationLabel>? labels,
    Object? activeDraftLabel = _unset,
    Object? pwmLevel = _unset,
    bool? fbmOn,
    List<RecordingFbmEvent>? fbmEvents,
    Object? lastError = _unset,
  }) {
    return RecordingState(
      status: status ?? this.status,
      experimentId:
          experimentId == _unset ? this.experimentId : experimentId as String?,
      displayName:
          displayName == _unset ? this.displayName : displayName as String?,
      sampleCount: sampleCount ?? this.sampleCount,
      activeSegmentId:
          activeSegmentId == _unset
              ? this.activeSegmentId
              : activeSegmentId as String?,
      segments: segments ?? this.segments,
      gaps: gaps ?? this.gaps,
      labels: labels ?? this.labels,
      activeDraftLabel:
          activeDraftLabel == _unset
              ? this.activeDraftLabel
              : activeDraftLabel as AnnotationLabel?,
      pwmLevel: pwmLevel == _unset ? this.pwmLevel : pwmLevel as int?,
      fbmOn: fbmOn ?? this.fbmOn,
      fbmEvents: fbmEvents ?? this.fbmEvents,
      lastError:
          lastError == _unset ? this.lastError : lastError as RecordingFailure?,
    );
  }

  @override
  List<Object?> get props => [
    status,
    experimentId,
    displayName,
    sampleCount,
    activeSegmentId,
    segments,
    gaps,
    labels,
    activeDraftLabel,
    pwmLevel,
    fbmOn,
    fbmEvents,
    lastError,
  ];
}
