part of 'rt_eeg_data_bloc.dart';

sealed class RtEegData {}

/// Пачка новых отсчётов из одного notify-пакета BLE.
///
/// Отсчёты приходят пачкой, а не по одному, специально: тяжёлая работа
/// ([SignalProcessor.filterSignal] по всему буферу, `emit`, перерисовка
/// графика) выполняется раз на пачку, а не 250 раз в секунду. Живому графику
/// не нужна частота отсчётов — достаточно плавной картинки.
class NewEegSamplesReceived extends RtEegData {
  final List<double> samples;

  NewEegSamplesReceived({required this.samples});
}

class NewSettings extends RtEegData {
  final EegSettings newSettings;

  NewSettings({required this.newSettings});
}

class RtEegResetRequested extends RtEegData {
  RtEegResetRequested();
}
