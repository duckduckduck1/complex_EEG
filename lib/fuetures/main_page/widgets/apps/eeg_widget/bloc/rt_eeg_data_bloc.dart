import 'package:bloc/bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/proccesing_math/signal_processor.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

part 'rt_eeg_data_vent.dart';
part 'rt_eeg_data_state.dart';

/// Живые данные графиков: сигнал, спектр и мощность ритмов.
///
/// Держит кольцевой буфер на [bufferSize] последних отсчётов (степень двойки —
/// требование FFT) и сам считает спектр и полосы, отдавая виджетам готовое
/// состояние. Данные живут только в памяти: `signal.bin` графики не читают.
///
/// Фильтры здесь — **только для картинки**; запись использует свой потоковый
/// фильтр. Точка на графике ритмов добавляется раз в секунду, а не на каждый
/// отсчёт. `RtEegResetRequested` обнуляет буферы — его шлёт вкладка на старте
/// записи, чтобы эксперимент начинался с чистых графиков.
class RtEegDataBloc extends Bloc<RtEegData, RtEegState> {
  List<double> _eegData = [];
  List<double> _fillterEegData = [];
  List<FlSpot> timePlotData = [];
  List<FlSpot> freqPlotData = [];
  List<FlSpot> fitDataPlot = [];
  List<FlSpot> filtSpectrum = [];

  final List<FlSpot> _deltaPowerOverTime = [];
  final List<FlSpot> _thetaPowerOverTime = [];
  final List<FlSpot> _alphaPowerOverTime = [];
  final List<FlSpot> _betaPowerOverTime = [];
  int _lastBandUpdateTime = 0;
  int _lastFftSample = 0;

  int sampleCounter = 0;
  final processor = SignalProcessor(1024, 250.0, FillterSettings());
  final double sampleRate;
  EegSettings eegSettings = EegSettings(
    EegIsShowingSettings(),
    FillterSettings(),
  );
  int bufferSize = 1024;
  double minFreqY = -60;

  RtEegDataBloc(this.sampleRate) : super(DataInitial()) {
    on<NewEegSamplesReceived>(_onNewSamples);
    on<NewSettings>(_onNewFilter);
    on<RtEegResetRequested>(_onResetRequested);
  }

  void _onNewSamples(NewEegSamplesReceived event, Emitter<RtEegState> emit) {
    if (event.samples.isEmpty) {
      return;
    }
    try {
      // Дешёвая покадровая бухгалтерия по каждому отсчёту: сырой буфер, точки
      // времени, ритмы раз в секунду. Дорогое (фильтрация всего буфера, emit,
      // FFT) вынесено ниже — раз на всю пачку.
      for (final value in event.samples) {
        _eegData.add(value);
        if (_eegData.length > bufferSize) {
          _eegData = _eegData.sublist(_eegData.length - bufferSize);
        }

        timePlotData.add(FlSpot(sampleCounter / sampleRate, value));
        if (timePlotData.length > bufferSize) {
          timePlotData = timePlotData.sublist(timePlotData.length - bufferSize);
        }

        if (sampleCounter - _lastBandUpdateTime >= sampleRate) {
          _lastBandUpdateTime = sampleCounter;
          final bandPowers = processor.computeBandPowers(filtSpectrum);
          _deltaPowerOverTime.add(
            FlSpot(sampleCounter / sampleRate, bandPowers['Delta'] ?? 0),
          );
          _thetaPowerOverTime.add(
            FlSpot(sampleCounter / sampleRate, bandPowers['Theta'] ?? 0),
          );
          _alphaPowerOverTime.add(
            FlSpot(sampleCounter / sampleRate, bandPowers['Alpha'] ?? 0),
          );
          _betaPowerOverTime.add(
            FlSpot(sampleCounter / sampleRate, bandPowers['Beta'] ?? 0),
          );
          if (_deltaPowerOverTime.length > 60) {
            _deltaPowerOverTime.removeAt(0);
            _thetaPowerOverTime.removeAt(0);
            _alphaPowerOverTime.removeAt(0);
            _betaPowerOverTime.removeAt(0);
          }
        }
        sampleCounter++;
      }

      // Раз на пачку: перефильтровать буфер и пересобрать отфильтрованный график
      // по тем же x, что у сырого окна.
      _fillterEegData = processor.filterSignal(_eegData);
      if (_fillterEegData.length > bufferSize) {
        _fillterEegData = _fillterEegData.sublist(
          _fillterEegData.length - bufferSize,
        );
      }
      final window = timePlotData.length;
      final filteredTail = _fillterEegData.length - window;
      fitDataPlot = [
        for (var i = 0; i < window; i++)
          FlSpot(
            timePlotData[i].x,
            (filteredTail + i) >= 0 &&
                    (filteredTail + i) < _fillterEegData.length
                ? _fillterEegData[filteredTail + i]
                : 0,
          ),
      ];

      emit(
        DataUpdated(
          timePlotData,
          freqPlotData,
          fitDataPlot,
          filtSpectrum,
          deltaPower: _deltaPowerOverTime,
          thetaPower: _thetaPowerOverTime,
          alphaPower: _alphaPowerOverTime,
          betaPower: _betaPowerOverTime,
        ),
      );

      // Спектр считаем не чаще, чем раз в ~128 отсчётов: FFT дорогой.
      if (sampleCounter - _lastFftSample >= 128) {
        _lastFftSample = sampleCounter;
        freqPlotData = processor.computeFrequencySpectrum(_eegData);
        filtSpectrum = processor.computeFrequencySpectrum(_fillterEegData);
      }
    } catch (_) {
      // Сбойную пачку пропускаем: real-time поток не должен падать целиком
      // из-за одной некорректной точки.
    }
  }

  void _onNewFilter(NewSettings event, Emitter<RtEegState> emit) {
    eegSettings = event.newSettings;
    processor.settings = event.newSettings.fillterSettings;
  }

  void _onResetRequested(RtEegResetRequested event, Emitter<RtEegState> emit) {
    _eegData = [];
    _fillterEegData = [];
    timePlotData = [];
    freqPlotData = [];
    fitDataPlot = [];
    filtSpectrum = [];
    _deltaPowerOverTime.clear();
    _thetaPowerOverTime.clear();
    _alphaPowerOverTime.clear();
    _betaPowerOverTime.clear();
    _lastBandUpdateTime = 0;
    _lastFftSample = 0;
    sampleCounter = 0;
    emit(DataInitial());
  }
}
