import 'dart:collection';

import 'package:bloc/bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:eeg_app_max30003_stm32/core/signal/butterworth_chain.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/proccesing_math/signal_processor.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';

part 'rt_eeg_data_vent.dart';
part 'rt_eeg_data_state.dart';

/// Живые данные графиков: сигнал, спектр и мощность ритмов.
///
/// Держит последние [bufferSize] отсчётов (степень двойки — требование FFT) и
/// сам считает спектр и полосы. Данные живут только в памяти: `signal.bin`
/// графики не читают.
///
/// Два решения, от которых здесь всё зависит:
///
/// **Фильтр потоковый.** Каждый отсчёт проходит через [ButterworthChain] один
/// раз, каскад проектируется только при смене настроек. Раньше на каждый отсчёт
/// перефильтровывался весь буфер целиком с пересчётом коэффициентов — 250 × 1024
/// операций в секунду на устройство, и это не только грело процессор: общий
/// экземпляр `Butterworth` перенастраивался под каждый каскад, состояние ФНЧ
/// протекало в ФВЧ, а прогон с нуля перезапускал переходный процесс. Картинка
/// расходилась с тем, что писалось в файл. Теперь график и запись считают
/// одинаково — каскад у них общий.
///
/// **Буферы кольцевые.** [ListQueue] даёт O(1) на оба конца. Раньше на каждый
/// отсчёт делалось три `sublist`, то есть три новых списка по 1024 элемента —
/// около 6 МБ мусора в секунду на устройство.
///
/// Состояние наружу списков не отдаёт: виджеты берут точки геттерами в момент
/// отрисовки. Перерисовка ограничена частотой кадров, поэтому списки собираются
/// 60 раз в секунду вместо 250 — и никто не держит ссылку на буфер, который
/// bloc продолжает менять.
///
/// Фильтры здесь — **только для картинки**; запись использует свой каскад.
/// Точка на графике ритмов добавляется раз в секунду, а не на каждый отсчёт.
/// [RtEegResetRequested] обнуляет буферы — его шлёт вкладка на старте записи,
/// чтобы эксперимент начинался с чистых графиков.
class RtEegDataBloc extends Bloc<RtEegData, RtEegState> {
  RtEegDataBloc(this.sampleRate) : super(DataInitial()) {
    _rebuildFilter();
    on<NewEegDataReceived>(_onNewData);
    on<NewSettings>(_onNewFilter);
    on<RtEegResetRequested>(_onResetRequested);
  }

  final double sampleRate;
  final int bufferSize = 1024;

  final processor = SignalProcessor(1024, 250.0);

  /// Последние применённые настройки. Владеет ими `EegSettingsCubit`, сюда они
  /// приезжают событием — bloc их только читает, чтобы пересобрать каскад.
  EegSettings eegSettings = const EegSettings.initial();

  final ListQueue<double> _raw = ListQueue<double>(1024);
  final ListQueue<double> _filtered = ListQueue<double>(1024);
  final ListQueue<FlSpot> _rawPlot = ListQueue<FlSpot>(1024);
  final ListQueue<FlSpot> _filteredPlot = ListQueue<FlSpot>(1024);

  final ListQueue<FlSpot> _deltaPower = ListQueue<FlSpot>(_bandHistory);
  final ListQueue<FlSpot> _thetaPower = ListQueue<FlSpot>(_bandHistory);
  final ListQueue<FlSpot> _alphaPower = ListQueue<FlSpot>(_bandHistory);
  final ListQueue<FlSpot> _betaPower = ListQueue<FlSpot>(_bandHistory);

  /// Сколько секунд истории ритмов держим на графике.
  static const int _bandHistory = 60;

  /// Через сколько отсчётов пересчитывать спектр. Полный буфер меняется не так
  /// быстро, чтобы считать FFT чаще.
  static const int _fftEveryNSamples = 128;

  ButterworthChain _filter = ButterworthChain.passThrough();
  List<FlSpot> _spectrum = const [];
  List<FlSpot> _filteredSpectrum = const [];

  int _sampleCounter = 0;
  int _lastBandUpdate = 0;
  int _sinceFft = 0;

  /// Точки для графиков. Собираются на чтении, а не на каждый отсчёт: читают их
  /// виджеты в момент отрисовки, то есть не чаще кадра.
  List<FlSpot> get rawSpots => _rawPlot.toList(growable: false);
  List<FlSpot> get filteredSpots => _filteredPlot.toList(growable: false);
  List<FlSpot> get spectrum => _spectrum;
  List<FlSpot> get filteredSpectrum => _filteredSpectrum;
  List<FlSpot> get deltaPower => _deltaPower.toList(growable: false);
  List<FlSpot> get thetaPower => _thetaPower.toList(growable: false);
  List<FlSpot> get alphaPower => _alphaPower.toList(growable: false);
  List<FlSpot> get betaPower => _betaPower.toList(growable: false);

  void _onNewData(NewEegDataReceived event, Emitter<RtEegState> emit) {
    final raw = event.newEegData;
    if (!raw.isFinite) {
      // Битый отсчёт пропускаем: поток реального времени не должен вставать
      // из-за одной точки, но и в фильтр NaN пускать нельзя — он отравит
      // состояние каскада навсегда.
      return;
    }
    final filtered = _filter.filter(raw);
    final seconds = _sampleCounter / sampleRate;

    _push(_raw, raw, bufferSize);
    _push(_filtered, filtered, bufferSize);
    _push(_rawPlot, FlSpot(seconds, raw), bufferSize);
    _push(_filteredPlot, FlSpot(seconds, filtered), bufferSize);

    if (_sampleCounter - _lastBandUpdate >= sampleRate) {
      _lastBandUpdate = _sampleCounter;
      final bandPowers = processor.computeBandPowers(_filteredSpectrum);
      _push(
        _deltaPower,
        FlSpot(seconds, bandPowers['Delta'] ?? 0),
        _bandHistory,
      );
      _push(
        _thetaPower,
        FlSpot(seconds, bandPowers['Theta'] ?? 0),
        _bandHistory,
      );
      _push(
        _alphaPower,
        FlSpot(seconds, bandPowers['Alpha'] ?? 0),
        _bandHistory,
      );
      _push(_betaPower, FlSpot(seconds, bandPowers['Beta'] ?? 0), _bandHistory);
    }

    _sampleCounter++;

    if (++_sinceFft >= _fftEveryNSamples && _raw.length == bufferSize) {
      _sinceFft = 0;
      _spectrum = processor.computeFrequencySpectrum(_raw);
      _filteredSpectrum = processor.computeFrequencySpectrum(_filtered);
    }

    emit(DataUpdated(_sampleCounter));
  }

  static void _push<T>(ListQueue<T> queue, T value, int limit) {
    queue.addLast(value);
    if (queue.length > limit) {
      queue.removeFirst();
    }
  }

  void _onNewFilter(NewSettings event, Emitter<RtEegState> emit) {
    final previous = eegSettings.fillterSettings;
    eegSettings = event.newSettings;
    // Пересобираем каскад, только если поменялись сами фильтры. Событие
    // настроек приходит и на смену состава графиков — от кнопок «Спектр»,
    // «Ритмы», «Фильтр», — а те к сигналу отношения не имеют. Раньше каскад
    // пересобирался на любое событие, и каждое нажатие этих кнопок роняло
    // график переходным процессом фильтра с нуля.
    if (event.newSettings.fillterSettings != previous) {
      _rebuildFilter();
    }
  }

  /// Пересобирает каскад под текущие настройки и перефильтровывает видимое окно.
  ///
  /// Вызывается только при смене настроек фильтра — на потоке отсчётов каскад
  /// не трогается вообще, иначе состояние сбрасывалось бы постоянно.
  ///
  /// Окно пересчитывается целиком, из сырых отсчётов: иначе на графике осталась
  /// бы половина, отфильтрованная старыми настройками, а новый каскад начал бы с
  /// нуля и дал заметный провал у правого края. Это единственный прогон по
  /// буферу — один на нажатие, а не на каждый отсчёт, как было раньше.
  void _rebuildFilter() {
    final settings = eegSettings.fillterSettings;
    _filter = ButterworthChain.build(
      sampleRateHz: sampleRate,
      lowPassHz: settings.isLpOn ? settings.lp : null,
      highPassHz: settings.isHpOn ? settings.hp : null,
      notchHz: settings.isNotchOn ? settings.notch : null,
    );

    // Один проход по сырому окну: заодно считаем и значения, и точки графика.
    // Порядок важен — каскад с состоянием, значения должны идти как во времени.
    final rawValues = _raw.toList(growable: false);
    final rawSpotsSnapshot = _rawPlot.toList(growable: false);
    _filtered.clear();
    _filteredPlot.clear();
    for (var i = 0; i < rawValues.length; i++) {
      final value = _filter.filter(rawValues[i]);
      _filtered.addLast(value);
      _filteredPlot.addLast(FlSpot(rawSpotsSnapshot[i].x, value));
    }
  }

  void _onResetRequested(RtEegResetRequested event, Emitter<RtEegState> emit) {
    _raw.clear();
    _filtered.clear();
    _rawPlot.clear();
    _filteredPlot.clear();
    _deltaPower.clear();
    _thetaPower.clear();
    _alphaPower.clear();
    _betaPower.clear();
    _spectrum = const [];
    _filteredSpectrum = const [];
    _sampleCounter = 0;
    _lastBandUpdate = 0;
    _sinceFft = 0;
    // Каскад тоже с нуля: иначе новый эксперимент начнётся с хвостом старого
    // переходного процесса.
    _rebuildFilter();
    emit(DataInitial());
  }
}
