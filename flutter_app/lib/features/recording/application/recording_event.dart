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
