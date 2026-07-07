import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/domain/recording_ports.dart';

abstract interface class RecordingBlocFactory {
  RecordingBloc create({required FbmTransport fbmTransport});
}
