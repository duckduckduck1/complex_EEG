import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/core/signal/butterworth_chain.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

void main() {
  late RtEegDataBloc bloc;

  setUp(() => bloc = RtEegDataBloc(250));
  tearDown(() async => bloc.close());

  void feed(Iterable<double> samples) {
    for (final sample in samples) {
      bloc.add(NewEegDataReceived(newEegData: sample));
    }
  }

  void enableLowPass(double hz) {
    bloc.add(
      NewSettings(
        newSettings: EegSettings(
          const EegIsShowingSettings(),
          FillterSettings(isLpOn: true, lp: hz),
        ),
      ),
    );
  }

  test('буфер графика не растёт дальше своего размера', () async {
    feed(List<double>.generate(3000, (i) => i.toDouble()));
    await pumpEventQueue();

    expect(bloc.rawSpots, hasLength(bloc.bufferSize));
    expect(bloc.filteredSpots, hasLength(bloc.bufferSize));
    // Осталось именно последнее окно, а не первое.
    expect(bloc.rawSpots.last.y, 2999);
  });

  test('фильтр графика совпадает с потоковым каскадом', () async {
    // Главная гарантия шага: картинка считается тем же способом, что и запись.
    // Раньше график перефильтровывал весь буфер заново на каждый отсчёт и
    // показывал не тот сигнал, что уходил в файл.
    const hz = 20.0;
    enableLowPass(hz);
    await pumpEventQueue();

    final input = List<double>.generate(
      500,
      (i) => sin(2 * pi * 3 * i / 250) * 50 + sin(2 * pi * 80 * i / 250) * 20,
    );
    feed(input);
    await pumpEventQueue();

    final reference = ButterworthChain.build(sampleRateHz: 250, lowPassHz: hz);
    final expected = input.map(reference.filter).toList(growable: false);

    final actual = bloc.filteredSpots;
    expect(actual, hasLength(input.length));
    for (var i = 0; i < actual.length; i++) {
      expect(actual[i].y, closeTo(expected[i], 1e-9));
    }
  });

  test('фильтр не пересобирается на потоке отсчётов', () async {
    // Пересборка каскада сбрасывала бы состояние и перезапускала переходный
    // процесс на каждом отсчёте — именно это и было раньше.
    enableLowPass(20);
    await pumpEventQueue();

    feed(List<double>.filled(400, 100));
    await pumpEventQueue();

    final tail = bloc.filteredSpots.skip(300).map((spot) => spot.y);
    // На постоянном входе ФНЧ обязан выйти на полку около самого входа.
    for (final value in tail) {
      expect(value, closeTo(100, 1));
    }
  });

  test('смена настроек пересобирает каскад', () async {
    feed(List<double>.filled(300, 100));
    await pumpEventQueue();
    final unfiltered = bloc.filteredSpots.last.y;
    expect(unfiltered, 100, reason: 'без фильтров сигнал проходит как есть');

    enableLowPass(1);
    feed(List<double>.filled(5, 100));
    await pumpEventQueue();

    // Каскад начал считать с нуля, поэтому первые отсчёты после включения
    // ещё далеко от полки.
    expect(bloc.filteredSpots.last.y, lessThan(100));
  });

  test('смена состава графиков фильтр не трогает', () async {
    // Кнопки «Спектр», «Ритмы» и «Фильтр» шлют то же событие настроек, что и
    // ползунки. Раньше каскад пересобирался на любое из них, и каждое нажатие
    // роняло график переходным процессом фильтра с нуля.
    enableLowPass(20);
    feed(List<double>.filled(600, 100));
    await pumpEventQueue();
    final before = bloc.filteredSpots.map((spot) => spot.y).toList();

    bloc.add(
      NewSettings(
        newSettings: EegSettings(
          const EegIsShowingSettings(isFftShowing: true),
          bloc.eegSettings.fillterSettings,
        ),
      ),
    );
    await pumpEventQueue();

    expect(
      bloc.filteredSpots.map((spot) => spot.y).toList(),
      before,
      reason: 'сигнал не должен дёрнуться от переключения графиков',
    );
  });

  test('смена фильтра пересчитывает всё видимое окно', () async {
    // Иначе на графике осталась бы половина, отфильтрованная старыми
    // настройками, а новый каскад начал бы с нуля и дал провал у правого края.
    feed(List<double>.filled(600, 100));
    await pumpEventQueue();

    enableLowPass(1);
    await pumpEventQueue();

    final spots = bloc.filteredSpots;
    expect(spots, hasLength(600));
    // Начало окна — переходный процесс, конец уже на полке: значит новым
    // каскадом прогнали всю историю, а не только новые отсчёты.
    expect(spots.first.y, lessThan(50));
    expect(spots.last.y, closeTo(100, 5));
  });

  test('битый отсчёт не отравляет фильтр', () async {
    enableLowPass(20);
    await pumpEventQueue();

    feed(List<double>.filled(100, 10));
    bloc.add(NewEegDataReceived(newEegData: double.nan));
    feed(List<double>.filled(100, 10));
    await pumpEventQueue();

    // NaN в состоянии IIR остался бы там навсегда, поэтому такой отсчёт
    // отбрасывается до фильтра.
    expect(bloc.filteredSpots.last.y.isFinite, isTrue);
    expect(bloc.filteredSpots, hasLength(200));
  });

  test('сброс очищает буферы и состояние фильтра', () async {
    enableLowPass(20);
    feed(List<double>.filled(500, 100));
    await pumpEventQueue();
    expect(bloc.filteredSpots, isNotEmpty);

    bloc.add(RtEegResetRequested());
    await pumpEventQueue();

    expect(bloc.rawSpots, isEmpty);
    expect(bloc.filteredSpots, isEmpty);
    expect(bloc.spectrum, isEmpty);
    expect(bloc.deltaPower, isEmpty);

    // Новый эксперимент начинается без хвоста прежнего переходного процесса.
    feed(List<double>.filled(5, 100));
    await pumpEventQueue();
    expect(bloc.filteredSpots.first.y, lessThan(100));
  });

  test('история ритмов не растёт бесконечно', () async {
    feed(List<double>.generate(250 * 70, (i) => sin(i / 10) * 30));
    await pumpEventQueue();

    expect(bloc.deltaPower.length, lessThanOrEqualTo(60));
    expect(bloc.betaPower.length, lessThanOrEqualTo(60));
  });
}
