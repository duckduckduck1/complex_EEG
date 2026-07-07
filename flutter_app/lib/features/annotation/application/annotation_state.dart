import 'package:equatable/equatable.dart';

import '../domain/annotation_models.dart';

enum AnnotationValidationCode {
  unknownLabelType,
  wrongLabelKind,
  stateAlreadyOpen,
  noActiveState,
  segmentMismatch,
  pointOutsideSegment,
  intervalOutsideSegment,
  emptyInterval,
  labelNotFound,
}

class AnnotationValidationError extends Equatable {
  const AnnotationValidationError(this.code, this.message);

  final AnnotationValidationCode code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}

class AnnotationState extends Equatable {
  const AnnotationState({
    this.labels = const <AnnotationLabel>[],
    this.activeDraftLabel,
    this.selectedLabelId,
    this.validationError,
    this.isSaving = false,
  });

  final List<AnnotationLabel> labels;
  final AnnotationLabel? activeDraftLabel;
  final String? selectedLabelId;
  final AnnotationValidationError? validationError;
  final bool isSaving;

  static const _unset = Object();

  AnnotationState copyWith({
    List<AnnotationLabel>? labels,
    Object? activeDraftLabel = _unset,
    Object? selectedLabelId = _unset,
    Object? validationError = _unset,
    bool? isSaving,
  }) {
    return AnnotationState(
      labels: labels ?? this.labels,
      activeDraftLabel:
          activeDraftLabel == _unset
              ? this.activeDraftLabel
              : activeDraftLabel as AnnotationLabel?,
      selectedLabelId:
          selectedLabelId == _unset
              ? this.selectedLabelId
              : selectedLabelId as String?,
      validationError:
          validationError == _unset
              ? this.validationError
              : validationError as AnnotationValidationError?,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
    labels,
    activeDraftLabel,
    selectedLabelId,
    validationError,
    isSaving,
  ];
}
