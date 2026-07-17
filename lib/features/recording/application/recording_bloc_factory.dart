import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

abstract interface class RecordingBlocFactory {
  RecordingBloc create({required FbmTransport fbmTransport});
}
