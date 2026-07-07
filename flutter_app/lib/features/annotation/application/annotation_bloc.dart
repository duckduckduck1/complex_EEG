import 'package:flutter_bloc/flutter_bloc.dart';

import 'annotation_event.dart';
import 'annotation_state.dart';
import '../domain/annotation_models.dart';
import '../domain/annotation_ports.dart';

class AnnotationBloc extends Bloc<AnnotationEvent, AnnotationState> {
  AnnotationBloc({
    required String experimentId,
    required AnnotationJournal journal,
    required AnnotationIdGenerator idGenerator,
    required List<LabelType> labelTypes,
    AnnotationClock clock = const SystemAnnotationClock(),
  }) : _experimentId = experimentId,
       _journal = journal,
       _idGenerator = idGenerator,
       _clock = clock,
       _labelTypes = {for (final type in labelTypes) type.id: type},
       super(const AnnotationState()) {
    on<StateLabelStarted>(_onStateLabelStarted);
    on<ActiveStateLabelClosed>(_onActiveStateLabelClosed);
    on<ActiveStateLabelClosedAtSegmentEnd>(_onActiveStateLabelClosedAtEnd);
    on<PointEventLabelAdded>(_onPointEventLabelAdded);
    on<ExcludeIntervalLabelAdded>(_onExcludeIntervalLabelAdded);
    on<AnnotationDeleted>(_onAnnotationDeleted);
  }

  final String _experimentId;
  final AnnotationJournal _journal;
  final AnnotationIdGenerator _idGenerator;
  final AnnotationClock _clock;
  final Map<String, LabelType> _labelTypes;

  Future<void> _onStateLabelStarted(
    StateLabelStarted event,
    Emitter<AnnotationState> emit,
  ) async {
    if (state.activeDraftLabel != null) {
      emit(_withError(AnnotationValidationCode.stateAlreadyOpen));
      return;
    }
    final type = _typeFor(event.labelTypeId, AnnotationKind.state);
    if (type == null) {
      emit(_withLabelTypeError(event.labelTypeId, AnnotationKind.state));
      return;
    }
    final validationError = _validatePoint(event.position);
    if (validationError != null) {
      emit(state.copyWith(validationError: validationError));
      return;
    }

    final label = AnnotationLabel(
      id: _idGenerator.nextId(),
      kind: type.kind,
      labelTypeId: type.id,
      segmentId: event.position.segmentId,
      startSegmentSampleIndex: event.position.segmentSampleIndex,
      globalStartSampleIndex: event.position.globalSampleIndex,
      startedAtWallClock: event.position.wallClockTime,
      note: event.note,
      isDraft: true,
    );

    await _persist(
      emit,
      action: () => _appendJournal('annotation_created', label),
      onSuccess:
          () => state.copyWith(
            labels: [...state.labels, label],
            activeDraftLabel: label,
            selectedLabelId: label.id,
            validationError: null,
          ),
    );
  }

  Future<void> _onActiveStateLabelClosed(
    ActiveStateLabelClosed event,
    Emitter<AnnotationState> emit,
  ) async {
    await _closeActiveState(event.position, emit);
  }

  Future<void> _onActiveStateLabelClosedAtEnd(
    ActiveStateLabelClosedAtSegmentEnd event,
    Emitter<AnnotationState> emit,
  ) async {
    final draft = state.activeDraftLabel;
    if (draft == null) {
      emit(_withError(AnnotationValidationCode.noActiveState));
      return;
    }
    final segmentStartSample =
        draft.globalStartSampleIndex - draft.startSegmentSampleIndex;
    final position = AnnotationPoint(
      segmentId: event.segmentId,
      segmentStartSample: segmentStartSample,
      segmentEndSample: event.segmentEndSample,
      segmentSampleIndex: event.segmentEndSample - segmentStartSample,
      wallClockTime: event.wallClockTime,
    );
    await _closeActiveState(position, emit);
  }

  Future<void> _onPointEventLabelAdded(
    PointEventLabelAdded event,
    Emitter<AnnotationState> emit,
  ) async {
    final type = _typeFor(event.labelTypeId, AnnotationKind.event);
    if (type == null) {
      emit(_withLabelTypeError(event.labelTypeId, AnnotationKind.event));
      return;
    }
    final validationError = _validatePoint(event.position);
    if (validationError != null) {
      emit(state.copyWith(validationError: validationError));
      return;
    }

    final label = AnnotationLabel(
      id: _idGenerator.nextId(),
      kind: type.kind,
      labelTypeId: type.id,
      segmentId: event.position.segmentId,
      startSegmentSampleIndex: event.position.segmentSampleIndex,
      globalStartSampleIndex: event.position.globalSampleIndex,
      startedAtWallClock: event.position.wallClockTime,
      note: event.note,
    );

    await _persist(
      emit,
      action: () => _appendJournal('annotation_created', label),
      onSuccess:
          () => state.copyWith(
            labels: [...state.labels, label],
            selectedLabelId: label.id,
            validationError: null,
          ),
    );
  }

  Future<void> _onExcludeIntervalLabelAdded(
    ExcludeIntervalLabelAdded event,
    Emitter<AnnotationState> emit,
  ) async {
    final type = _typeFor(event.labelTypeId, AnnotationKind.exclude);
    if (type == null) {
      emit(_withLabelTypeError(event.labelTypeId, AnnotationKind.exclude));
      return;
    }
    final validationError = _validateInterval(event.start, event.end);
    if (validationError != null) {
      emit(state.copyWith(validationError: validationError));
      return;
    }

    final label = AnnotationLabel(
      id: _idGenerator.nextId(),
      kind: type.kind,
      labelTypeId: type.id,
      segmentId: event.start.segmentId,
      startSegmentSampleIndex: event.start.segmentSampleIndex,
      globalStartSampleIndex: event.start.globalSampleIndex,
      startedAtWallClock: event.start.wallClockTime,
      endSegmentSampleIndex: event.end.segmentSampleIndex,
      globalEndSampleIndex: event.end.globalSampleIndex,
      endedAtWallClock: event.end.wallClockTime,
      note: event.note,
    );

    await _persist(
      emit,
      action: () => _appendJournal('annotation_created', label),
      onSuccess:
          () => state.copyWith(
            labels: [...state.labels, label],
            selectedLabelId: label.id,
            validationError: null,
          ),
    );
  }

  Future<void> _onAnnotationDeleted(
    AnnotationDeleted event,
    Emitter<AnnotationState> emit,
  ) async {
    final target = state.labels.where((label) => label.id == event.labelId);
    if (target.isEmpty) {
      emit(_withError(AnnotationValidationCode.labelNotFound));
      return;
    }

    await _persist(
      emit,
      action:
          () => _journal.appendAnnotation({
            'type': 'annotation_deleted',
            'experiment_id': _experimentId,
            'timestamp': _clock.now().toUtc().toIso8601String(),
            'label_id': event.labelId,
          }),
      onSuccess:
          () => state.copyWith(
            labels: state.labels
                .where((label) => label.id != event.labelId)
                .toList(growable: false),
            activeDraftLabel:
                state.activeDraftLabel?.id == event.labelId
                    ? null
                    : state.activeDraftLabel,
            selectedLabelId: null,
            validationError: null,
          ),
    );
  }

  Future<void> _closeActiveState(
    AnnotationPoint end,
    Emitter<AnnotationState> emit,
  ) async {
    final draft = state.activeDraftLabel;
    if (draft == null) {
      emit(_withError(AnnotationValidationCode.noActiveState));
      return;
    }
    if (draft.segmentId != end.segmentId) {
      emit(_withError(AnnotationValidationCode.segmentMismatch));
      return;
    }
    final validationError = _validateInterval(
      AnnotationPoint(
        segmentId: draft.segmentId,
        segmentStartSample:
            draft.globalStartSampleIndex - draft.startSegmentSampleIndex,
        segmentSampleIndex: draft.startSegmentSampleIndex,
        wallClockTime: draft.startedAtWallClock,
        segmentEndSample: end.segmentEndSample,
      ),
      end,
    );
    if (validationError != null) {
      emit(state.copyWith(validationError: validationError));
      return;
    }

    final closed = draft.closeAt(end);
    await _persist(
      emit,
      action: () => _appendJournal('annotation_updated', closed),
      onSuccess:
          () => state.copyWith(
            labels: state.labels
                .map((label) => label.id == closed.id ? closed : label)
                .toList(growable: false),
            activeDraftLabel: null,
            selectedLabelId: closed.id,
            validationError: null,
          ),
    );
  }

  Future<void> _persist(
    Emitter<AnnotationState> emit, {
    required Future<void> Function() action,
    required AnnotationState Function() onSuccess,
  }) async {
    emit(state.copyWith(isSaving: true, validationError: null));
    try {
      await action();
      emit(onSuccess().copyWith(isSaving: false));
    } catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          validationError: _error(
            AnnotationValidationCode.journalWriteFailed,
            error.toString(),
          ),
        ),
      );
    }
  }

  LabelType? _typeFor(String id, AnnotationKind expectedKind) {
    final type = _labelTypes[id];
    if (type == null || type.kind != expectedKind || !type.isActive) {
      return null;
    }
    return type;
  }

  AnnotationValidationError? _validatePoint(AnnotationPoint point) {
    if (point.segmentSampleIndex < 0) {
      return _error(AnnotationValidationCode.pointOutsideSegment);
    }
    if (point.globalSampleIndex >= point.segmentEndSample) {
      return _error(AnnotationValidationCode.pointOutsideSegment);
    }
    return null;
  }

  AnnotationValidationError? _validateInterval(
    AnnotationPoint start,
    AnnotationPoint end,
  ) {
    if (start.segmentId != end.segmentId ||
        start.segmentStartSample != end.segmentStartSample ||
        start.segmentEndSample != end.segmentEndSample) {
      return _error(AnnotationValidationCode.segmentMismatch);
    }
    if (end.segmentSampleIndex <= start.segmentSampleIndex) {
      return _error(AnnotationValidationCode.emptyInterval);
    }
    if (start.segmentSampleIndex < 0) {
      return _error(AnnotationValidationCode.intervalOutsideSegment);
    }
    if (end.globalSampleIndex > end.segmentEndSample) {
      return _error(AnnotationValidationCode.intervalOutsideSegment);
    }
    return null;
  }

  AnnotationState _withLabelTypeError(String id, AnnotationKind expectedKind) {
    final existing = _labelTypes[id];
    return state.copyWith(
      validationError: _error(
        existing == null
            ? AnnotationValidationCode.unknownLabelType
            : AnnotationValidationCode.wrongLabelKind,
        'Label type "$id" is not ${expectedKind.name}',
      ),
    );
  }

  AnnotationState _withError(AnnotationValidationCode code) {
    return state.copyWith(validationError: _error(code));
  }

  AnnotationValidationError _error(
    AnnotationValidationCode code, [
    String? message,
  ]) {
    return AnnotationValidationError(code, message ?? code.name);
  }

  Future<void> _appendJournal(String type, AnnotationLabel label) {
    return _journal.appendAnnotation({
      'type': type,
      'experiment_id': _experimentId,
      'timestamp': _clock.now().toUtc().toIso8601String(),
      'label': label.toJournalJson(),
    });
  }
}
