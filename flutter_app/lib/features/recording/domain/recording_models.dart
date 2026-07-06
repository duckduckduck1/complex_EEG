import 'package:equatable/equatable.dart';

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
    this.displayName,
    this.metadata = const <String, Object?>{},
    this.filters = const RecordingFilters(),
    this.sampleRateHz = 250,
  });

  final String rootDirectory;
  final String? displayName;
  final Map<String, Object?> metadata;
  final RecordingFilters filters;
  final int sampleRateHz;

  @override
  List<Object?> get props => [
    rootDirectory,
    displayName,
    metadata,
    filters,
    sampleRateHz,
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
    this.lastError,
  });

  final RecordingStatus status;
  final String? experimentId;
  final String? displayName;
  final int sampleCount;
  final String? activeSegmentId;
  final List<RecordingSegment> segments;
  final List<RecordingGap> gaps;
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
    lastError,
  ];
}
