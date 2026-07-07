import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/application/recording_bloc_factory.dart';
import 'package:iot/features/recording/data/file_experiment_storage.dart';
import 'package:iot/features/recording/data/iir_streaming_filter.dart';
import 'package:iot/features/recording/data/ulid_experiment_id_generator.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

class FileRecordingBlocFactory implements RecordingBlocFactory {
  const FileRecordingBlocFactory();

  @override
  RecordingBloc create({required FbmTransport fbmTransport}) {
    return RecordingBloc(
      storage: FileExperimentStorage(),
      filterFactory: const IirStreamingFilterFactory(),
      idGenerator: UlidExperimentIdGenerator(),
      fbmTransport: fbmTransport,
    );
  }
}
