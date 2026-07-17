import 'recording_models.dart';

abstract interface class ExperimentStorage {
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
  });

  Future<void> appendSamples(List<int> samples);

  Future<void> appendJournal(Map<String, Object?> event, {bool flush = false});

  Future<void> flush();

  Future<void> writeExperimentJson(Map<String, Object?> experimentJson);

  Future<void> close();
}

abstract interface class StreamingFilter {
  int filter(int sampleMicrovolts);
}

abstract interface class StreamingFilterFactory {
  StreamingFilter create(RecordingFilters filters);
}

abstract interface class RecordingClock {
  DateTime now();
}

abstract interface class ExperimentIdGenerator {
  String nextId();
}

abstract interface class FbmTransport {
  Future<bool> setLed({required bool on, required int pwmByte});
}

class PassThroughStreamingFilter implements StreamingFilter {
  const PassThroughStreamingFilter();

  @override
  int filter(int sampleMicrovolts) => sampleMicrovolts;
}

class PassThroughStreamingFilterFactory implements StreamingFilterFactory {
  const PassThroughStreamingFilterFactory();

  @override
  StreamingFilter create(RecordingFilters filters) =>
      const PassThroughStreamingFilter();
}

class SystemRecordingClock implements RecordingClock {
  const SystemRecordingClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
