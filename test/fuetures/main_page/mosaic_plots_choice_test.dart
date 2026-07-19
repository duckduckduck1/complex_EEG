import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_panel_plots_choice.dart';

void main() {
  test('по умолчанию видны сигнал и ритмы', () {
    const choice = MosaicPlotsChoice();
    expect(choice.signal, isTrue);
    expect(choice.bands, isTrue);
    expect(choice.spectrum, isFalse);
  });

  test('спектр включается и выключается', () {
    const choice = MosaicPlotsChoice();
    final withSpectrum = choice.toggle(MosaicPlotKind.spectrum);
    expect(withSpectrum.spectrum, isTrue);
    expect(withSpectrum.toggle(MosaicPlotKind.spectrum).spectrum, isFalse);
  });

  test('последний включённый график выключить нельзя', () {
    // Пустая панель не несёт ничего, но продолжает занимать место в сетке.
    const onlySignal = MosaicPlotsChoice(signal: true, bands: false);
    expect(onlySignal.canToggleOff(MosaicPlotKind.signal), isFalse);
    expect(
      onlySignal.toggle(MosaicPlotKind.signal),
      onlySignal,
      reason: 'состав не меняется',
    );
  });

  test('выключить не последний график можно', () {
    const both = MosaicPlotsChoice();
    expect(both.canToggleOff(MosaicPlotKind.bands), isTrue);
    final onlySignal = both.toggle(MosaicPlotKind.bands);
    expect(onlySignal.bands, isFalse);
    expect(onlySignal.signal, isTrue);
  });

  test('выключение доходит до последнего графика и там останавливается', () {
    var choice = const MosaicPlotsChoice();
    for (final kind in MosaicPlotKind.values) {
      choice = choice.toggle(kind);
    }
    expect(
      choice.enabledCount,
      greaterThanOrEqualTo(1),
      reason: 'панель без графиков недопустима ни при какой последовательности',
    );
  });
}
