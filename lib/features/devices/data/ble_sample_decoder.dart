import '../../../core/signal/eeg_sample.dart';
import '../domain/device_signal_config.dart';

/// Декодер потока отсчётов устройства в значения [EegSample] (мкВ).
///
/// Разбирает payload BLE-notify группами по 3 байта, восстанавливает знак
/// 18-битного значения и переводит его в микровольты. Неполный «хвост» байтов
/// буферизуется и склеивается со следующим payload, чтобы не терять
/// выравнивание потока (см. docs/reference/device_packet.md).
///
/// Декодер хранит состояние (буфер хвоста), поэтому на каждое подключение
/// устройства создаётся свой экземпляр.
class BleSampleDecoder {
  BleSampleDecoder({DeviceSignalConfig config = DeviceSignalConfig.stand1})
    : _config = config;

  final DeviceSignalConfig _config;
  final List<int> _tail = <int>[];

  /// Сколько байтов сейчас в буфере «хвоста» (для диагностики и тестов).
  int get bufferedByteCount => _tail.length;

  /// Декодировать очередной payload, вернув готовые отсчёты.
  List<EegSample> addPayload(List<int> payload) {
    final bytes = <int>[..._tail, ...payload];
    _tail.clear();

    final fullGroups = bytes.length ~/ 3;
    final samples = <EegSample>[];
    var offset = 0;
    for (var group = 0; group < fullGroups; group++) {
      samples.add(
        _decodeSample(bytes[offset], bytes[offset + 1], bytes[offset + 2]),
      );
      offset += 3;
    }
    if (offset < bytes.length) {
      _tail.addAll(bytes.sublist(offset));
    }
    return samples;
  }

  /// Сбросить буфер «хвоста» (например, при переоткрытии подключения).
  void reset() => _tail.clear();

  EegSample _decodeSample(int b0, int b1, int b2) {
    var adc = ((b0 & 0xff) << 10) | ((b1 & 0xff) << 2) | ((b2 & 0xff) >> 6);
    if (adc >= _config.signedThreshold) {
      adc -= _config.signedRange;
    }
    final microvolts = (adc * _config.microvoltsPerAdcUnit).round();
    return EegSample(valueMicrovolts: microvolts);
  }
}
