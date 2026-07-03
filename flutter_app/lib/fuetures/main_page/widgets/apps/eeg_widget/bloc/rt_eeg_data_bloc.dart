import 'package:bloc/bloc.dart';
import 'package:fftea/impl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/bloc/proccesing_math/signal_processor.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';
import 'package:meta/meta.dart';

part 'rt_eeg_data_vent.dart';
part 'rt_eeg_data_state.dart';

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

  int sampleCounter = 0;
  final processor = SignalProcessor(1024, 250.0, FillterSettings());
  final double sampleRate;
  EegSettings eegSettings = EegSettings(
    EegIsShowingSettings(),
    FillterSettings(),
  );
  int bufferSize = 1024;
  int fftFlag = 0;
  double minFreqY = -60;
  late final FFT _fft;

  RtEegDataBloc(this.sampleRate) : super(DataInitial()) {
    on<NewEegDataReceived>(_onNewData);
    on<NewSettings>(_onNewFilter);
  }

  void _onNewData(NewEegDataReceived event, Emitter<RtEegState> emit) {
    try {
      // Обновляем raw data

      _eegData.add(event.newEegData);

      if (_eegData.length > bufferSize) {
        _eegData = _eegData.sublist(_eegData.length - bufferSize);
      }
      _fillterEegData = processor.filterSignal(_eegData);
      if (_fillterEegData.length > bufferSize) {
        _fillterEegData = _fillterEegData.sublist(
          _fillterEegData.length - bufferSize,
        );
      }

      timePlotData.add(FlSpot(sampleCounter / sampleRate, _eegData.last));
      fitDataPlot.add(FlSpot(sampleCounter / sampleRate, _fillterEegData.last));
      if (timePlotData.length > bufferSize) {
        timePlotData = timePlotData.sublist(timePlotData.length - bufferSize);
        fitDataPlot = fitDataPlot.sublist(fitDataPlot.length - bufferSize);
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

        // Ограничиваем размер буфера (например, последние 60 секунд)
        if (_deltaPowerOverTime.length > 60) {
          _deltaPowerOverTime.removeAt(0);
          _thetaPowerOverTime.removeAt(0);
          _alphaPowerOverTime.removeAt(0);
          _betaPowerOverTime.removeAt(0);
        }
      }
      sampleCounter++;

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
      if (fftFlag == 128) {
        freqPlotData = processor.computeFrequencySpectrum(_eegData);
        filtSpectrum = processor.computeFrequencySpectrum(_fillterEegData);
      } else {
        fftFlag++;
      }
    } catch (e) {}
  }

  void _onNewFilter(NewSettings event, Emitter<RtEegState> emit) {
    eegSettings = event.newSettings;
    processor.settings = event.newSettings.fillterSettings;
  }
}
