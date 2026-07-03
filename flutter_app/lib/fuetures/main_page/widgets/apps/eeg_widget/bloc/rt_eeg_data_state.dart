part of 'rt_eeg_data_bloc.dart';

@immutable
sealed class RtEegState {}

final class DataInitial extends RtEegState {}

class DataUpdated extends RtEegState {
  final List<FlSpot> newData;
  final List<FlSpot> spectrum;
  final List<FlSpot> filterData;
  final List<FlSpot> filtSpectrum;
  final List<FlSpot> deltaPower;
  final List<FlSpot> thetaPower;
  final List<FlSpot> alphaPower;
  final List<FlSpot> betaPower;

  DataUpdated(
    this.newData,
    this.spectrum,
    this.filterData,
    this.filtSpectrum, {
    this.deltaPower = const [],
    this.thetaPower = const [],
    this.alphaPower = const [],
    this.betaPower = const [],
  });
}
