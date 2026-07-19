import 'package:equatable/equatable.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
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

/// Занята ли запись настолько, что вкладку закрывать нельзя.
///
/// Одно правило на всех: его спрашивает и `TabBloc` (не даёт закрыть), и панель
/// вкладок (объясняет оператору, почему крестик не сработал). Пауза по обрыву
/// сюда тоже входит — эксперимент ещё не завершён, его можно продолжить.
bool isRecordingBusy(RecordingStatus? status) => switch (status) {
  RecordingStatus.preparing ||
  RecordingStatus.recording ||
  RecordingStatus.pausedByDisconnect ||
  RecordingStatus.stopping => true,
  _ => false,
};

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

/// Почему сеанс ФБМ закончился.
enum FbmEndReason {
  /// Оператор нажал «Свет выкл».
  manual('manual'),

  /// Истекло время, выставленное таймером автовыключения.
  autoOffTimer('auto_off_timer'),

  /// Связь оборвалась. Команда «погасить» могла не доехать до устройства —
  /// смотреть `end_command_delivered`.
  connectionLost('connection_lost'),

  /// Запись остановили, не погасив свет вручную.
  recordingStopped('recording_stopped');

  const FbmEndReason(this.jsonValue);

  final String jsonValue;
}

/// Один сеанс горения ФБМ: включили — погасло.
///
/// В json это одна запись, а не пара «включили»/«выключили»: оператору нужна
/// длительность сеанса, а не два момента, между которыми надо вычитать самому.
/// Пока свет горит, запись уже лежит в снимке json с пометкой `in_progress` —
/// снимок пишется каждые полминуты, и незакрытый сеанс виден сразу, а не
/// появляется задним числом. Отдельные моменты включения и выключения никуда не
/// делись: они остаются строками в `journal.ndjson`, который пишется на лету.
class RecordingFbmSession extends Equatable {
  const RecordingFbmSession({
    required this.segmentId,
    required this.startSample,
    required this.startedAtWallClock,
    required this.pwmLevel,
    required this.pwmByte,
    required this.startCommandDelivered,
    this.endSample,
    this.endedAtWallClock,
    this.endReason,
    this.endCommandDelivered,
    this.inProgress = false,
  });

  final String segmentId;
  final int startSample;
  final DateTime startedAtWallClock;

  /// Яркость: если её меняли на горящем свете, здесь последнее значение —
  /// сеанс сменой яркости не прерывается.
  final int pwmLevel;
  final int pwmByte;
  final bool startCommandDelivered;

  final int? endSample;
  final DateTime? endedAtWallClock;
  final FbmEndReason? endReason;
  final bool? endCommandDelivered;

  /// Ставится только у копии для снимка json: сеанс ещё идёт, а `end_sample`
  /// в записи — момент снимка, а не настоящее выключение.
  final bool inProgress;

  bool get isOpen => endSample == null;

  int? get durationSamples =>
      endSample == null ? null : endSample! - startSample;

  RecordingFbmSession close({
    required int endSample,
    required DateTime endedAtWallClock,
    required FbmEndReason endReason,
    required bool endCommandDelivered,
  }) {
    return RecordingFbmSession(
      segmentId: segmentId,
      startSample: startSample,
      startedAtWallClock: startedAtWallClock,
      pwmLevel: pwmLevel,
      pwmByte: pwmByte,
      startCommandDelivered: startCommandDelivered,
      endSample: endSample,
      endedAtWallClock: endedAtWallClock,
      endReason: endReason,
      endCommandDelivered: endCommandDelivered,
    );
  }

  /// Копия для снимка json: сеанс ещё идёт, но длительность уже видна.
  ///
  /// Причину конца не выдумываем — её просто нет, пока свет горит.
  RecordingFbmSession snapshotAt({
    required int sampleCount,
    required DateTime wallClock,
  }) {
    return RecordingFbmSession(
      segmentId: segmentId,
      startSample: startSample,
      startedAtWallClock: startedAtWallClock,
      pwmLevel: pwmLevel,
      pwmByte: pwmByte,
      startCommandDelivered: startCommandDelivered,
      endSample: sampleCount,
      endedAtWallClock: wallClock,
      inProgress: true,
    );
  }

  RecordingFbmSession withPwm({required int pwmLevel, required int pwmByte}) {
    return RecordingFbmSession(
      segmentId: segmentId,
      startSample: startSample,
      startedAtWallClock: startedAtWallClock,
      pwmLevel: pwmLevel,
      pwmByte: pwmByte,
      startCommandDelivered: startCommandDelivered,
      endSample: endSample,
      endedAtWallClock: endedAtWallClock,
      endReason: endReason,
      endCommandDelivered: endCommandDelivered,
      inProgress: inProgress,
    );
  }

  Map<String, Object?> toJson() => {
    'segment_id': segmentId,
    'start_sample': startSample,
    // Дублируем время в чч:мм:сс — читать глазами, не переводя семплы.
    'start_time': formatClockFromSamples(startSample),
    'started_at_wall_clock': startedAtWallClock.toUtc().toIso8601String(),
    if (endSample != null) 'end_sample': endSample,
    if (endSample != null) 'end_time': formatClockFromSamples(endSample!),
    if (endedAtWallClock != null)
      'ended_at_wall_clock': endedAtWallClock!.toUtc().toIso8601String(),
    if (durationSamples != null) 'duration_samples': durationSamples,
    if (durationSamples != null)
      'duration': formatClockFromSamples(durationSamples!),
    'pwm_level': pwmLevel,
    'pwm_byte': pwmByte,
    'start_command_delivered': startCommandDelivered,
    if (endReason != null) 'end_reason': endReason!.jsonValue,
    if (endCommandDelivered != null)
      'end_command_delivered': endCommandDelivered,
    if (inProgress) 'in_progress': true,
  };

  @override
  List<Object?> get props => [
    segmentId,
    startSample,
    startedAtWallClock,
    pwmLevel,
    pwmByte,
    startCommandDelivered,
    endSample,
    endedAtWallClock,
    endReason,
    endCommandDelivered,
    inProgress,
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
    'start_time': formatClockFromSamples(startSample),
    if (endSample != null) 'end_time': formatClockFromSamples(endSample!),
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
    'time': formatClockFromSamples(sampleIndex),
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
    this.filters = const RecordingFilters(),
    this.pwmLevel,
    this.fbmAutoOffSeconds,
    this.fbmSessions = const <RecordingFbmSession>[],
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

  /// Фильтры, выбранные при старте записи. Их же вкладка применяет к графику,
  /// чтобы оператор видел ровно то, что пишется, и не выставлял руками заново.
  final RecordingFilters filters;

  final int? pwmLevel;

  /// Через сколько секунд после включения гасить свет автоматически.
  /// `null` — только вручную.
  final int? fbmAutoOffSeconds;

  final List<RecordingFbmSession> fbmSessions;
  final RecordingFailure? lastError;

  /// Идущий сеанс ФБМ, если свет горит.
  ///
  /// Открытый сеанс — единственный источник правды о том, горит ли свет и с
  /// какого отсчёта. Раньше рядом жили отдельные `fbmOn` и `fbmOnSampleIndex`,
  /// и это уже стоило нам бага: поле забыли в `props`, Equatable счёл состояние
  /// прежним, и bloc проглотил `emit`. Одно поле рассинхронизировать нельзя.
  RecordingFbmSession? get openFbmSession {
    if (fbmSessions.isEmpty) return null;
    final last = fbmSessions.last;
    return last.isOpen ? last : null;
  }

  bool get fbmOn => openFbmSession != null;

  /// Сколько отсчётов свет горит прямо сейчас; `null`, если он погашен.
  int? get fbmElapsedSamples {
    final session = openFbmSession;
    return session == null ? null : sampleCount - session.startSample;
  }

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
    RecordingFilters? filters,
    Object? pwmLevel = _unset,
    Object? fbmAutoOffSeconds = _unset,
    List<RecordingFbmSession>? fbmSessions,
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
      filters: filters ?? this.filters,
      pwmLevel: pwmLevel == _unset ? this.pwmLevel : pwmLevel as int?,
      fbmAutoOffSeconds:
          fbmAutoOffSeconds == _unset
              ? this.fbmAutoOffSeconds
              : fbmAutoOffSeconds as int?,
      fbmSessions: fbmSessions ?? this.fbmSessions,
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
    filters,
    pwmLevel,
    fbmAutoOffSeconds,
    fbmSessions,
    lastError,
  ];
}
