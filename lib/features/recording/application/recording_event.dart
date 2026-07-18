part of 'recording_bloc.dart';

sealed class RecordingEvent extends Equatable {
  const RecordingEvent();

  @override
  List<Object?> get props => const [];
}

final class RecordingStartRequested extends RecordingEvent {
  const RecordingStartRequested(this.config);

  final RecordingStartConfig config;

  @override
  List<Object?> get props => [config];
}

final class RecordingSamplesReceived extends RecordingEvent {
  const RecordingSamplesReceived(this.samplesMicrovolts);

  final List<int> samplesMicrovolts;

  @override
  List<Object?> get props => [samplesMicrovolts];
}

final class RecordingStopRequested extends RecordingEvent {
  const RecordingStopRequested();
}

final class RecordingConnectionLost extends RecordingEvent {
  const RecordingConnectionLost();
}

final class RecordingConnectionResumed extends RecordingEvent {
  const RecordingConnectionResumed();
}

final class FbmOnRequested extends RecordingEvent {
  const FbmOnRequested();
}

final class FbmOffRequested extends RecordingEvent {
  const FbmOffRequested();
}

/// Настроить автовыключение ФБМ: через сколько секунд после включения гасить
/// свет самому. `null` — только вручную.
final class FbmAutoOffChanged extends RecordingEvent {
  const FbmAutoOffChanged(this.seconds);

  final int? seconds;

  @override
  List<Object?> get props => [seconds];
}

final class FbmPwmChanged extends RecordingEvent {
  const FbmPwmChanged(this.pwmLevel);

  final int pwmLevel;

  @override
  List<Object?> get props => [pwmLevel];
}

final class RecordingStateLabelStarted extends RecordingEvent {
  const RecordingStateLabelStarted({required this.labelTypeId, this.note});

  final String labelTypeId;
  final String? note;

  @override
  List<Object?> get props => [labelTypeId, note];
}

final class RecordingActiveStateLabelClosed extends RecordingEvent {
  const RecordingActiveStateLabelClosed();
}

final class RecordingPointLabelAdded extends RecordingEvent {
  const RecordingPointLabelAdded({required this.labelTypeId, this.note});

  final String labelTypeId;
  final String? note;

  @override
  List<Object?> get props => [labelTypeId, note];
}

/// Ручное добавление метки-состояния интервалом по времени. Границы —
/// **глобальные** индексы отсчётов (от начала записи, как ось графика); сегмент
/// подтягивается автоматически по этим границам.
final class RecordingManualIntervalAdded extends RecordingEvent {
  const RecordingManualIntervalAdded({
    required this.labelTypeId,
    required this.startGlobalSampleIndex,
    required this.endGlobalSampleIndex,
    this.note,
  });

  final String labelTypeId;
  final int startGlobalSampleIndex;
  final int endGlobalSampleIndex;
  final String? note;

  @override
  List<Object?> get props => [
    labelTypeId,
    startGlobalSampleIndex,
    endGlobalSampleIndex,
    note,
  ];
}

final class RecordingAnnotationDeleted extends RecordingEvent {
  const RecordingAnnotationDeleted(this.labelId);

  final String labelId;

  @override
  List<Object?> get props => [labelId];
}
