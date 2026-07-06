import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/features/recording/domain/recording_models.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

part 'recording_event.dart';

class RecordingBloc extends Bloc<RecordingEvent, RecordingState> {
  RecordingBloc({
    required ExperimentStorage storage,
    required StreamingFilterFactory filterFactory,
    required ExperimentIdGenerator idGenerator,
    RecordingClock clock = const SystemRecordingClock(),
  }) : _storage = storage,
       _filterFactory = filterFactory,
       _idGenerator = idGenerator,
       _clock = clock,
       super(const RecordingState()) {
    on<RecordingStartRequested>(_onStartRequested);
    on<RecordingSamplesReceived>(_onSamplesReceived);
    on<RecordingStopRequested>(_onStopRequested);
  }

  final ExperimentStorage _storage;
  final StreamingFilterFactory _filterFactory;
  final ExperimentIdGenerator _idGenerator;
  final RecordingClock _clock;

  RecordingStartConfig? _config;
  StreamingFilter _filter = const PassThroughStreamingFilter();

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

    final stateToFinalize = state;
    emit(state.copyWith(status: RecordingStatus.stopping));

    try {
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
      },
      'segments': segments
          .where((segment) => segment.endSample != null)
          .map((segment) => segment.toJson())
          .toList(growable: false),
      'gaps': gaps.map((gap) => gap.toJson()).toList(growable: false),
      'labels': const <Object>[],
      'fbm_events': const <Object>[],
    };
  }

  Map<String, Object?> _journalEvent({
    required String type,
    required String experimentId,
    required DateTime timestamp,
    String? segmentId,
    int? sampleIndex,
  }) {
    return {
      'type': type,
      'experiment_id': experimentId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (segmentId != null) 'segment_id': segmentId,
      if (sampleIndex != null) 'sample_index': sampleIndex,
    };
  }

  bool _canFinalize(RecordingStatus status) {
    return status == RecordingStatus.recording ||
        status == RecordingStatus.pausedByDisconnect;
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
        await _finalizeRecording(state);
      } catch (_) {
        await _safeCloseStorage();
      }
    } else {
      await _safeCloseStorage();
    }
    return super.close();
  }
}
