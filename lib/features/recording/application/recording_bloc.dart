import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/features/annotation/domain/annotation_models.dart';
import 'package:iot/features/recording/domain/recording_models.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

part 'recording_event.dart';

class RecordingBloc extends Bloc<RecordingEvent, RecordingState> {
  RecordingBloc({
    required ExperimentStorage storage,
    required StreamingFilterFactory filterFactory,
    required ExperimentIdGenerator idGenerator,
    required FbmTransport fbmTransport,
    List<LabelType> labelTypes = defaultLabelTypes,
    RecordingClock clock = const SystemRecordingClock(),
  }) : _storage = storage,
       _filterFactory = filterFactory,
       _idGenerator = idGenerator,
       _fbmTransport = fbmTransport,
       _labelTypes = {for (final type in labelTypes) type.id: type},
       _clock = clock,
       super(const RecordingState()) {
    on<RecordingStartRequested>(_onStartRequested);
    on<RecordingSamplesReceived>(_onSamplesReceived);
    on<RecordingStopRequested>(_onStopRequested);
    on<RecordingConnectionLost>(_onConnectionLost);
    on<RecordingConnectionResumed>(_onConnectionResumed);
    on<FbmOnRequested>(_onFbmOnRequested);
    on<FbmOffRequested>(_onFbmOffRequested);
    on<FbmPwmChanged>(_onFbmPwmChanged);
    on<RecordingStateLabelStarted>(_onStateLabelStarted);
    on<RecordingActiveStateLabelClosed>(_onActiveStateLabelClosed);
    on<RecordingPointLabelAdded>(_onPointLabelAdded);
    on<RecordingExcludeIntervalAdded>(_onExcludeIntervalAdded);
    on<RecordingAnnotationDeleted>(_onAnnotationDeleted);
  }

  final ExperimentStorage _storage;
  final StreamingFilterFactory _filterFactory;
  final ExperimentIdGenerator _idGenerator;
  final FbmTransport _fbmTransport;
  final Map<String, LabelType> _labelTypes;
  final RecordingClock _clock;

  RecordingStartConfig? _config;
  StreamingFilter _filter = const PassThroughStreamingFilter();
  bool _connectionLostInProgress = false;
  bool _resumeAfterConnectionLost = false;
  int _nextLabelIndex = 1;

  Future<void> _onStartRequested(
    RecordingStartRequested event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status == RecordingStatus.preparing ||
        state.status == RecordingStatus.recording ||
        state.status == RecordingStatus.stopping) {
      return;
    }

    emit(const RecordingState(status: RecordingStatus.preparing));

    try {
      final experimentId = _idGenerator.nextId();
      final startedAt = _clock.now();
      _config = event.config;
      _filter = _filterFactory.create(event.config.filters);

      await _storage.createExperiment(
        rootDirectory: event.config.rootDirectory,
        experimentId: experimentId,
      );
      await _storage.appendJournal(
        _journalEvent(
          type: 'experiment_started',
          experimentId: experimentId,
          timestamp: startedAt,
        ),
        flush: true,
      );

      final segment = RecordingSegment(
        segmentId: 'seg_1',
        startSample: 0,
        startedAtWallClock: startedAt,
      );
      await _storage.appendJournal(
        _journalEvent(
          type: 'segment_started',
          experimentId: experimentId,
          timestamp: startedAt,
          segmentId: segment.segmentId,
          sampleIndex: segment.startSample,
        ),
        flush: true,
      );

      emit(
        RecordingState(
          status: RecordingStatus.recording,
          experimentId: experimentId,
          displayName: event.config.displayName,
          activeSegmentId: segment.segmentId,
          segments: [segment],
          pwmLevel: event.config.pwmLevel,
        ),
      );
    } catch (error) {
      await _safeCloseStorage();
      emit(
        RecordingState(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onSamplesReceived(
    RecordingSamplesReceived event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording ||
        event.samplesMicrovolts.isEmpty) {
      return;
    }

    try {
      final filtered = event.samplesMicrovolts
          .map(_filter.filter)
          .toList(growable: false);
      await _storage.appendSamples(filtered);
      emit(state.copyWith(sampleCount: state.sampleCount + filtered.length));
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onStopRequested(
    RecordingStopRequested event,
    Emitter<RecordingState> emit,
  ) async {
    if (!_canFinalize(state.status)) {
      return;
    }

    var stateToFinalize = state;
    emit(state.copyWith(status: RecordingStatus.stopping));

    try {
      stateToFinalize = await _autoCloseActiveLabel(
        stateToFinalize,
        timestamp: _clock.now(),
      );
      stateToFinalize = await _autoTurnFbmOff(
        stateToFinalize,
        allowUndelivered: true,
        reason: 'recording_stop',
      );
      emit(await _finalizeRecording(stateToFinalize));
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onConnectionLost(
    RecordingConnectionLost event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording) {
      return;
    }

    final experimentId = state.experimentId;
    if (experimentId == null || state.segments.isEmpty) {
      return;
    }

    _connectionLostInProgress = true;
    try {
      final lostAt = _clock.now();
      var stateBeforeLost = await _autoCloseActiveLabel(
        state,
        timestamp: lostAt,
      );
      stateBeforeLost = await _autoTurnFbmOff(
        stateBeforeLost,
        allowUndelivered: true,
        reason: 'connection_lost',
      );
      await _storage.flush();

      final segments = List<RecordingSegment>.from(stateBeforeLost.segments);
      final activeIndex = segments.indexWhere(
        (segment) => segment.segmentId == stateBeforeLost.activeSegmentId,
      );
      if (activeIndex >= 0 && !segments[activeIndex].isClosed) {
        final closed = segments[activeIndex].close(
          endSample: stateBeforeLost.sampleCount,
          endedAtWallClock: lostAt,
        );
        segments[activeIndex] = closed;
        await _storage.appendJournal(
          _journalEvent(
            type: 'segment_ended',
            experimentId: experimentId,
            timestamp: lostAt,
            segmentId: closed.segmentId,
            sampleIndex: closed.endSample,
          ),
          flush: true,
        );
      }

      await _storage.appendJournal(
        _journalEvent(
          type: 'connection_lost',
          experimentId: experimentId,
          timestamp: lostAt,
          sampleIndex: stateBeforeLost.sampleCount,
        ),
        flush: true,
      );

      emit(
        stateBeforeLost.copyWith(
          status: RecordingStatus.pausedByDisconnect,
          activeSegmentId: null,
          segments: segments,
          gaps: [
            ...stateBeforeLost.gaps,
            RecordingGap(
              startedAtWallClock: lostAt,
              sampleIndex: stateBeforeLost.sampleCount,
            ),
          ],
        ),
      );
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    } finally {
      _connectionLostInProgress = false;
      if (_resumeAfterConnectionLost && !isClosed) {
        _resumeAfterConnectionLost = false;
        add(const RecordingConnectionResumed());
      }
    }
  }

  Future<void> _onConnectionResumed(
    RecordingConnectionResumed event,
    Emitter<RecordingState> emit,
  ) async {
    if (_connectionLostInProgress) {
      _resumeAfterConnectionLost = true;
      return;
    }

    if (state.status != RecordingStatus.pausedByDisconnect) {
      return;
    }

    try {
      emit(await _resumeFromPaused(state));
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onFbmOnRequested(
    FbmOnRequested event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording || state.fbmOn) {
      return;
    }

    try {
      emit(
        await _applyFbmEvent(
          state,
          isOn: true,
          pwmLevel: state.pwmLevel ?? 50,
          sendCommand: true,
        ),
      );
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onFbmOffRequested(
    FbmOffRequested event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording || !state.fbmOn) {
      return;
    }

    try {
      emit(await _applyFbmEvent(state, isOn: false, sendCommand: true));
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onFbmPwmChanged(
    FbmPwmChanged event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording ||
        !_isValidPwmLevel(event.pwmLevel) ||
        state.pwmLevel == event.pwmLevel) {
      return;
    }

    if (!state.fbmOn) {
      emit(state.copyWith(pwmLevel: event.pwmLevel));
      return;
    }

    try {
      emit(
        await _applyFbmEvent(
          state,
          isOn: true,
          pwmLevel: event.pwmLevel,
          sendCommand: true,
        ),
      );
    } catch (error) {
      await _safeCloseStorage();
      emit(
        state.copyWith(
          status: RecordingStatus.failed,
          lastError: RecordingFailure(error.toString()),
        ),
      );
    }
  }

  Future<void> _onStateLabelStarted(
    RecordingStateLabelStarted event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording ||
        state.activeDraftLabel != null) {
      return;
    }
    final type = _labelType(event.labelTypeId, AnnotationKind.state);
    final segment = _activeSegment(state);
    final experimentId = state.experimentId;
    if (type == null || segment == null || experimentId == null) {
      return;
    }

    try {
      final position = _currentBoundaryPoint(state, segment);
      final label = AnnotationLabel(
        id: _nextLabelId(),
        kind: AnnotationKind.state,
        labelTypeId: type.id,
        segmentId: segment.segmentId,
        startSegmentSampleIndex: position.segmentSampleIndex,
        globalStartSampleIndex: position.globalSampleIndex,
        startedAtWallClock: position.wallClockTime,
        note: event.note,
        isDraft: true,
      );
      await _appendAnnotationJournal(
        type: 'annotation_created',
        experimentId: experimentId,
        label: label,
      );
      emit(
        state.copyWith(
          labels: [...state.labels, label],
          activeDraftLabel: label,
        ),
      );
    } catch (error) {
      emit(_annotationFailedState(error));
    }
  }

  Future<void> _onActiveStateLabelClosed(
    RecordingActiveStateLabelClosed event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording ||
        state.activeDraftLabel == null) {
      return;
    }

    try {
      emit(await _autoCloseActiveLabel(state, timestamp: _clock.now()));
    } catch (error) {
      emit(_annotationFailedState(error));
    }
  }

  Future<void> _onPointLabelAdded(
    RecordingPointLabelAdded event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording) {
      return;
    }
    final type = _labelType(event.labelTypeId, AnnotationKind.event);
    final segment = _activeSegment(state);
    final experimentId = state.experimentId;
    if (type == null || segment == null || experimentId == null) {
      return;
    }

    try {
      final position = _currentSamplePoint(state, segment);
      final label = AnnotationLabel(
        id: _nextLabelId(),
        kind: AnnotationKind.event,
        labelTypeId: type.id,
        segmentId: segment.segmentId,
        startSegmentSampleIndex: position.segmentSampleIndex,
        globalStartSampleIndex: position.globalSampleIndex,
        startedAtWallClock: position.wallClockTime,
        note: event.note,
      );
      await _appendAnnotationJournal(
        type: 'annotation_created',
        experimentId: experimentId,
        label: label,
      );
      emit(state.copyWith(labels: [...state.labels, label]));
    } catch (error) {
      emit(_annotationFailedState(error));
    }
  }

  Future<void> _onExcludeIntervalAdded(
    RecordingExcludeIntervalAdded event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.status != RecordingStatus.recording) {
      return;
    }
    final type = _labelType(event.labelTypeId, AnnotationKind.exclude);
    final segment = _activeSegment(state);
    final experimentId = state.experimentId;
    if (type == null || segment == null || experimentId == null) {
      return;
    }
    if (event.startSegmentSampleIndex < 0 ||
        event.endSegmentSampleIndex <= event.startSegmentSampleIndex ||
        segment.startSample + event.endSegmentSampleIndex > state.sampleCount) {
      return;
    }

    try {
      final timestamp = _clock.now();
      final label = AnnotationLabel(
        id: _nextLabelId(),
        kind: AnnotationKind.exclude,
        labelTypeId: type.id,
        segmentId: segment.segmentId,
        startSegmentSampleIndex: event.startSegmentSampleIndex,
        globalStartSampleIndex:
            segment.startSample + event.startSegmentSampleIndex,
        startedAtWallClock: timestamp,
        endSegmentSampleIndex: event.endSegmentSampleIndex,
        globalEndSampleIndex: segment.startSample + event.endSegmentSampleIndex,
        endedAtWallClock: timestamp,
        note: event.note,
      );
      await _appendAnnotationJournal(
        type: 'annotation_created',
        experimentId: experimentId,
        label: label,
      );
      emit(state.copyWith(labels: [...state.labels, label]));
    } catch (error) {
      emit(_annotationFailedState(error));
    }
  }

  Future<void> _onAnnotationDeleted(
    RecordingAnnotationDeleted event,
    Emitter<RecordingState> emit,
  ) async {
    final experimentId = state.experimentId;
    if (experimentId == null ||
        !state.labels.any((label) => label.id == event.labelId)) {
      return;
    }

    try {
      await _storage.appendJournal(
        _journalEvent(
          type: 'annotation_deleted',
          experimentId: experimentId,
          timestamp: _clock.now(),
          extra: {'label_id': event.labelId},
        ),
        flush: true,
      );
      emit(
        state.copyWith(
          labels: state.labels
              .where((label) => label.id != event.labelId)
              .toList(growable: false),
          activeDraftLabel:
              state.activeDraftLabel?.id == event.labelId
                  ? null
                  : state.activeDraftLabel,
        ),
      );
    } catch (error) {
      emit(_annotationFailedState(error));
    }
  }

  Future<RecordingState> _resumeFromPaused(RecordingState stateToResume) async {
    final experimentId = stateToResume.experimentId;
    if (experimentId == null || stateToResume.segments.isEmpty) {
      throw StateError('Recording is not initialized');
    }

    final resumedAt = _clock.now();
    final segment = RecordingSegment(
      segmentId: 'seg_${stateToResume.segments.length + 1}',
      startSample: stateToResume.sampleCount,
      startedAtWallClock: resumedAt,
    );
    final gaps = _closeLatestGap(stateToResume.gaps, resumedAt);

    await _storage.appendJournal(
      _journalEvent(
        type: 'connection_resumed',
        experimentId: experimentId,
        timestamp: resumedAt,
        sampleIndex: stateToResume.sampleCount,
      ),
      flush: true,
    );
    await _storage.appendJournal(
      _journalEvent(
        type: 'segment_started',
        experimentId: experimentId,
        timestamp: resumedAt,
        segmentId: segment.segmentId,
        sampleIndex: segment.startSample,
      ),
      flush: true,
    );

    return stateToResume.copyWith(
      status: RecordingStatus.recording,
      activeSegmentId: segment.segmentId,
      segments: [...stateToResume.segments, segment],
      gaps: gaps,
    );
  }

  Future<RecordingState> _finalizeRecording(
    RecordingState stateToFinalize,
  ) async {
    final experimentId = stateToFinalize.experimentId;
    final config = _config;
    if (experimentId == null ||
        config == null ||
        stateToFinalize.segments.isEmpty) {
      throw StateError('Recording is not initialized');
    }

    final stoppedAt = _clock.now();
    await _storage.flush();

    final segments = List<RecordingSegment>.from(stateToFinalize.segments);
    final activeIndex = segments.indexWhere(
      (segment) => segment.segmentId == stateToFinalize.activeSegmentId,
    );
    if (activeIndex >= 0 && !segments[activeIndex].isClosed) {
      final closed = segments[activeIndex].close(
        endSample: stateToFinalize.sampleCount,
        endedAtWallClock: stoppedAt,
      );
      segments[activeIndex] = closed;
      await _storage.appendJournal(
        _journalEvent(
          type: 'segment_ended',
          experimentId: experimentId,
          timestamp: stoppedAt,
          segmentId: closed.segmentId,
          sampleIndex: closed.endSample,
        ),
        flush: true,
      );
    }

    await _storage.appendJournal(
      _journalEvent(
        type: 'recording_stopped',
        experimentId: experimentId,
        timestamp: stoppedAt,
        sampleIndex: stateToFinalize.sampleCount,
      ),
      flush: true,
    );
    await _storage.writeExperimentJson(
      _buildExperimentJson(
        experimentId: experimentId,
        config: config,
        segments: segments,
        gaps: stateToFinalize.gaps,
        labels: stateToFinalize.labels,
        fbmEvents: stateToFinalize.fbmEvents,
      ),
    );
    await _storage.flush();
    await _storage.close();

    return stateToFinalize.copyWith(
      status: RecordingStatus.stopped,
      activeSegmentId: null,
      segments: segments,
    );
  }

  Map<String, Object?> _buildExperimentJson({
    required String experimentId,
    required RecordingStartConfig config,
    required List<RecordingSegment> segments,
    required List<RecordingGap> gaps,
    required List<AnnotationLabel> labels,
    required List<RecordingFbmEvent> fbmEvents,
  }) {
    return {
      'experiment_id': experimentId,
      if (config.displayName != null && config.displayName!.trim().isNotEmpty)
        'display_name': config.displayName!.trim(),
      'metadata': config.metadata,
      'recording': {
        'sample_rate_hz': config.sampleRateHz,
        'amplitude_unit': 'microvolts',
        'sample_encoding': 'int32_le',
        'filters': config.filters.toJson(),
        'pwm_level': config.pwmLevel,
      },
      'segments': segments
          .where((segment) => segment.endSample != null)
          .map((segment) => segment.toJson())
          .toList(growable: false),
      'gaps': gaps.map((gap) => gap.toJson()).toList(growable: false),
      'labels': labels
          .where((label) => !label.isDraft)
          .map((label) => label.toExperimentJson())
          .toList(growable: false),
      'fbm_events': fbmEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }

  Map<String, Object?> _journalEvent({
    required String type,
    required String experimentId,
    required DateTime timestamp,
    String? segmentId,
    int? sampleIndex,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return {
      'type': type,
      'experiment_id': experimentId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (segmentId != null) 'segment_id': segmentId,
      if (sampleIndex != null) 'sample_index': sampleIndex,
      ...extra,
    };
  }

  Future<RecordingState> _autoTurnFbmOff(
    RecordingState stateToUpdate, {
    bool allowUndelivered = false,
    String? reason,
  }) async {
    if (!stateToUpdate.fbmOn) {
      return stateToUpdate;
    }
    return _applyFbmEvent(
      stateToUpdate,
      isOn: false,
      sendCommand: true,
      allowUndelivered: allowUndelivered,
      reason: reason,
    );
  }

  Future<RecordingState> _autoCloseActiveLabel(
    RecordingState stateToUpdate, {
    required DateTime timestamp,
  }) async {
    final draft = stateToUpdate.activeDraftLabel;
    final experimentId = stateToUpdate.experimentId;
    if (draft == null || experimentId == null) {
      return stateToUpdate;
    }
    final segment = _activeSegment(stateToUpdate);
    if (segment == null || segment.segmentId != draft.segmentId) {
      return stateToUpdate;
    }

    final endSegmentSampleIndex =
        stateToUpdate.sampleCount - segment.startSample;
    if (endSegmentSampleIndex <= draft.startSegmentSampleIndex) {
      // Пустой интервал: отбрасываем черновик целиком, чтобы в списке и журнале
      // не оставалась «открытая» метка без пары.
      await _storage.appendJournal(
        _journalEvent(
          type: 'annotation_deleted',
          experimentId: experimentId,
          timestamp: timestamp,
          extra: {'label_id': draft.id},
        ),
        flush: true,
      );
      return stateToUpdate.copyWith(
        labels: stateToUpdate.labels
            .where((label) => label.id != draft.id)
            .toList(growable: false),
        activeDraftLabel: null,
      );
    }

    final closed = draft.closeAt(
      AnnotationPoint(
        segmentId: segment.segmentId,
        segmentStartSample: segment.startSample,
        segmentEndSample: stateToUpdate.sampleCount,
        segmentSampleIndex: endSegmentSampleIndex,
        wallClockTime: timestamp,
      ),
    );
    await _appendAnnotationJournal(
      type: 'annotation_updated',
      experimentId: experimentId,
      label: closed,
    );
    return stateToUpdate.copyWith(
      labels: stateToUpdate.labels
          .map((label) => label.id == closed.id ? closed : label)
          .toList(growable: false),
      activeDraftLabel: null,
    );
  }

  Future<RecordingState> _applyFbmEvent(
    RecordingState stateToUpdate, {
    required bool isOn,
    int? pwmLevel,
    required bool sendCommand,
    bool allowUndelivered = false,
    String? reason,
  }) async {
    final effectivePwmLevel = pwmLevel ?? stateToUpdate.pwmLevel;
    if (effectivePwmLevel == null || !_isValidPwmLevel(effectivePwmLevel)) {
      throw StateError('PWM level must be in range 1..99');
    }

    final experimentId = stateToUpdate.experimentId;
    final segment = _activeSegment(stateToUpdate);
    if (experimentId == null || segment == null) {
      throw StateError('Recording is not initialized');
    }

    final pwmByte = pwmByteFromLevel(effectivePwmLevel);
    var commandDelivered = false;
    if (sendCommand) {
      commandDelivered = await _fbmTransport.setLed(on: isOn, pwmByte: pwmByte);
      if (!commandDelivered && !allowUndelivered) {
        throw StateError('FBM command could not be delivered');
      }
    }

    final timestamp = _clock.now();
    final globalSampleIndex = _globalSampleIndex(
      segment: segment,
      sampleCount: stateToUpdate.sampleCount,
    );
    final segmentSampleIndex = globalSampleIndex - segment.startSample;
    final fbmEvent = RecordingFbmEvent(
      segmentId: segment.segmentId,
      segmentSampleIndex: segmentSampleIndex,
      globalSampleIndex: globalSampleIndex,
      wallClockTime: timestamp,
      isOn: isOn,
      pwmLevel: effectivePwmLevel,
      pwmByte: pwmByte,
      commandDelivered: commandDelivered,
      reason: reason,
    );

    await _storage.appendJournal(
      _journalEvent(
        type: 'fbm_event',
        experimentId: experimentId,
        timestamp: timestamp,
        segmentId: segment.segmentId,
        sampleIndex: globalSampleIndex,
        extra: fbmEvent.toJson(),
      ),
      flush: true,
    );

    return stateToUpdate.copyWith(
      fbmOn: isOn,
      pwmLevel: effectivePwmLevel,
      fbmEvents: [...stateToUpdate.fbmEvents, fbmEvent],
    );
  }

  RecordingSegment? _activeSegment(RecordingState stateToRead) {
    final activeSegmentId = stateToRead.activeSegmentId;
    if (activeSegmentId == null) {
      return null;
    }
    for (final segment in stateToRead.segments) {
      if (segment.segmentId == activeSegmentId) {
        return segment;
      }
    }
    return null;
  }

  LabelType? _labelType(String id, AnnotationKind kind) {
    final type = _labelTypes[id];
    if (type == null || !type.isActive || type.kind != kind) {
      return null;
    }
    return type;
  }

  AnnotationPoint _currentBoundaryPoint(
    RecordingState stateToRead,
    RecordingSegment segment,
  ) {
    return AnnotationPoint(
      segmentId: segment.segmentId,
      segmentStartSample: segment.startSample,
      segmentEndSample: stateToRead.sampleCount,
      segmentSampleIndex: stateToRead.sampleCount - segment.startSample,
      wallClockTime: _clock.now(),
    );
  }

  AnnotationPoint _currentSamplePoint(
    RecordingState stateToRead,
    RecordingSegment segment,
  ) {
    final globalSampleIndex = _globalSampleIndex(
      segment: segment,
      sampleCount: stateToRead.sampleCount,
    );
    return AnnotationPoint(
      segmentId: segment.segmentId,
      segmentStartSample: segment.startSample,
      segmentEndSample: stateToRead.sampleCount,
      segmentSampleIndex: globalSampleIndex - segment.startSample,
      wallClockTime: _clock.now(),
    );
  }

  String _nextLabelId() => 'label_${_nextLabelIndex++}';

  Future<void> _appendAnnotationJournal({
    required String type,
    required String experimentId,
    required AnnotationLabel label,
  }) {
    return _storage.appendJournal(
      _journalEvent(
        type: type,
        experimentId: experimentId,
        timestamp: _clock.now(),
        segmentId: label.segmentId,
        sampleIndex: label.globalStartSampleIndex,
        extra: {'label': label.toJournalJson()},
      ),
      flush: true,
    );
  }

  RecordingState _annotationFailedState(Object error) {
    return state.copyWith(
      status: RecordingStatus.failed,
      lastError: RecordingFailure(error.toString()),
    );
  }

  int _globalSampleIndex({
    required RecordingSegment segment,
    required int sampleCount,
  }) {
    final writtenInSegment = sampleCount - segment.startSample;
    if (writtenInSegment <= 0) {
      return segment.startSample;
    }
    return sampleCount - 1;
  }

  List<RecordingGap> _closeLatestGap(
    List<RecordingGap> gaps,
    DateTime endedAtWallClock,
  ) {
    if (gaps.isEmpty || gaps.last.endedAtWallClock != null) {
      return gaps;
    }
    return [
      ...gaps.take(gaps.length - 1),
      RecordingGap(
        startedAtWallClock: gaps.last.startedAtWallClock,
        endedAtWallClock: endedAtWallClock,
        sampleIndex: gaps.last.sampleIndex,
      ),
    ];
  }

  bool _canFinalize(RecordingStatus status) {
    return status == RecordingStatus.recording ||
        status == RecordingStatus.pausedByDisconnect;
  }

  bool _isValidPwmLevel(int pwmLevel) => pwmLevel >= 1 && pwmLevel <= 99;

  static int pwmByteFromLevel(int pwmLevel) {
    if (pwmLevel < 1 || pwmLevel > 99) {
      throw ArgumentError.value(pwmLevel, 'pwmLevel', 'must be in range 1..99');
    }
    return (pwmLevel * 255 / 100).round();
  }

  Future<void> _safeCloseStorage() async {
    try {
      await _storage.close();
    } catch (_) {
      // Ошибка закрытия не должна маскировать исходную ошибку записи.
    }
  }

  @override
  Future<void> close() async {
    if (_canFinalize(state.status)) {
      try {
        final stateToClose = await _autoTurnFbmOff(
          state,
          allowUndelivered: true,
          reason: 'bloc_close',
        );
        await _finalizeRecording(stateToClose);
      } catch (_) {
        await _safeCloseStorage();
      }
    } else {
      await _safeCloseStorage();
    }
    return super.close();
  }
}
