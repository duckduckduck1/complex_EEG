import 'package:eeg_app_max30003_stm32/core/signal/eeg_sample.dart';
import 'package:eeg_app_max30003_stm32/features/devices/data/ble_sample_decoder.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/device_signal_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleSampleDecoder (стенд 1)', () {
    late BleSampleDecoder decoder;

    setUp(() => decoder = BleSampleDecoder());

    test('нулевой отсчёт даёт 0 мкВ', () {
      expect(decoder.addPayload([0x00, 0x00, 0x00]), const [
        EegSample(valueMicrovolts: 0),
      ]);
    });

    test('отрицательная полная шкала (adc = 2^17) даёт -62500 мкВ', () {
      expect(decoder.addPayload([0x80, 0x00, 0x00]), const [
        EegSample(valueMicrovolts: -62500),
      ]);
    });

    test('положительная полная шкала (adc = 2^17 - 1) даёт 62500 мкВ', () {
      expect(decoder.addPayload([0x7f, 0xff, 0xc0]), const [
        EegSample(valueMicrovolts: 62500),
      ]);
    });

    test('старшие 6 бит b2 игнорируются', () {
      // b2 = 0x3F -> adc = 0; b2 = 0xC0 -> adc = 3.
      expect(decoder.addPayload([0x00, 0x00, 0x3f]), const [
        EegSample(valueMicrovolts: 0),
      ]);
      expect(decoder.addPayload([0x00, 0x00, 0xc0]), const [
        EegSample(valueMicrovolts: 1),
      ]);
    });

    test('несколько отсчётов в одном payload', () {
      final samples = decoder.addPayload([0x00, 0x00, 0x00, 0x80, 0x00, 0x00]);
      expect(samples, const [
        EegSample(valueMicrovolts: 0),
        EegSample(valueMicrovolts: -62500),
      ]);
    });

    test(
      'неполный «хвост» буферизуется и склеивается со следующим payload',
      () {
        // Хвост 2 байта + payload 3 байта = 5 байт: один полный отсчёт
        // (склеенный через границу) и новый остаток в 2 байта.
        final first = decoder.addPayload([0x80, 0x00]);
        expect(first, isEmpty);
        expect(decoder.bufferedByteCount, 2);

        final second = decoder.addPayload([0x00, 0x00, 0x00]);
        expect(second, const [EegSample(valueMicrovolts: -62500)]);
        expect(decoder.bufferedByteCount, 2);
      },
    );

    test('разрыв группы после 1 байта склеивается иначе, чем после 2 байт', () {
      // Хвост 1 байт + payload 5 байт = 6 байт: первая группа склеена из
      // хвоста и первых 2 байт payload, вторая группа целиком из payload,
      // остатка не остаётся (в отличие от кейса выше, где хвост 2 байта
      // и остаётся новый остаток в 2 байта).
      final first = decoder.addPayload([0x80]);
      expect(first, isEmpty);
      expect(decoder.bufferedByteCount, 1);

      final second = decoder.addPayload([0x00, 0x00, 0x7f, 0xff, 0xc0]);
      expect(second, const [
        EegSample(valueMicrovolts: -62500),
        EegSample(valueMicrovolts: 62500),
      ]);
      expect(decoder.bufferedByteCount, 0);
    });

    test('reset очищает буфер хвоста', () {
      decoder.addPayload([0x80]);
      expect(decoder.bufferedByteCount, 1);
      decoder.reset();
      expect(decoder.bufferedByteCount, 0);
    });
  });

  group('BleSampleDecoder (конфигурация тракта)', () {
    test('vRef/gain берутся из конфигурации устройства', () {
      final decoder = BleSampleDecoder(
        config: const DeviceSignalConfig(gain: 320),
      );
      expect(decoder.addPayload([0x80, 0x00, 0x00]), const [
        EegSample(valueMicrovolts: -31250),
      ]);
    });
  });
}
