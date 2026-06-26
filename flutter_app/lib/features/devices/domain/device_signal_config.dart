import 'package:equatable/equatable.dart';

/// Параметры аппаратного тракта устройства для декодирования сигнала.
///
/// `vRef` и `gain` — характеристики конкретного железа; держим их в
/// конфигурации, а не зашитыми в формулу по месту
/// (см. docs/reference/device_packet.md).
class DeviceSignalConfig extends Equatable {
  const DeviceSignalConfig({
    this.sampleRateHz = 250,
    this.adcModel = 'MAX30003',
    this.adcResolutionBits = 18,
    this.vRef = 1.0,
    this.gain = 160,
  });

  /// Частота дискретизации, Гц (на первом стенде фиксирована прошивкой).
  final int sampleRateHz;

  /// Модель АЦП.
  final String adcModel;

  /// Разрядность АЦП в битах.
  final int adcResolutionBits;

  /// Опорное напряжение тракта, В.
  final double vRef;

  /// Коэффициент усиления тракта.
  final double gain;

  /// Параметры первого стенда (JDY-16 + MAX30003).
  static const DeviceSignalConfig stand1 = DeviceSignalConfig();

  /// 2^(bits-1): половина шкалы знакового значения (2^17 для 18 бит).
  int get _halfScale => 1 << (adcResolutionBits - 1);

  /// Полный диапазон знакового значения (2^18 для 18 бит).
  int get signedRange => 1 << adcResolutionBits;

  /// Порог, выше которого значение трактуется как отрицательное.
  int get signedThreshold => _halfScale;

  /// Множитель перевода единицы АЦП в микровольты.
  ///
  /// `eeg_uv = adc / 2^(bits-1) * (vRef / gain) * 1e7`. Для первого стенда
  /// сворачивается в `≈ 0.476837 мкВ` на единицу АЦП.
  double get microvoltsPerAdcUnit => (vRef / gain) * 1e7 / _halfScale;

  @override
  List<Object?> get props => [
    sampleRateHz,
    adcModel,
    adcResolutionBits,
    vRef,
    gain,
  ];
}
