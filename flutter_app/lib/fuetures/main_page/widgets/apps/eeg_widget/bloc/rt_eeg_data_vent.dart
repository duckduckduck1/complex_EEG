part of 'rt_eeg_data_bloc.dart';

sealed class RtEegData {}

class NewEegDataReceived extends RtEegData {
  final double newEegData;

  NewEegDataReceived({required this.newEegData});
}

class NewSettings extends RtEegData {
  final EegSettings newSettings;

  NewSettings({required this.newSettings});
}
