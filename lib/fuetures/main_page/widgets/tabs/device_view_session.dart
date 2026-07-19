import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:eeg_app_max30003_stm32/features/devices/presentation/blocs/device_connection_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bridge.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/ble_page/bloc/device_eeg_bridge.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';

/// Всё, что живёт, пока устройство открыто в приложении: живые графики, мосты
/// от BLE к графикам и к записи, и сам bloc записи.
///
/// Раньше этим владел виджет вкладки: его `dispose` закрывал [RecordingBloc] и
/// [RtEegDataBloc]. Пока вкладка — единственное место, где устройство показано,
/// это работало. Как только тот же поток надо показать ещё и панелью мозаики,
/// владение видом становится опасным: уход вкладки из дерева оборвал бы идущую
/// запись. Поэтому сессия принадлежит `TabBloc`, а виды (вкладка, панель
/// мозаики) её только читают и не закрывают.
///
/// Подключение сюда **не входит**: [connection] принадлежит `SessionsCubit`,
/// закрытие вкладки не отключает устройство.
class DeviceViewSession {
  DeviceViewSession({
    required this.connection,
    required this.recordingBloc,
    this.title = '',
  }) : rtEegDataBloc = RtEegDataBloc(250) {
    _eegBridge = DeviceEegBridge(
      connection: connection,
      rtEegDataBloc: rtEegDataBloc,
    );
    _recordingBridge = RecordingBridge(
      connection: connection,
      recordingBloc: recordingBloc,
    );
    _recordingSub = recordingBloc.stream.listen(_onRecordingState);
  }

  /// BLoC подключения устройства; жизненным циклом владеет `SessionsCubit`.
  final DeviceConnectionBloc connection;

  /// Имя устройства для заголовков. Лежит здесь, а не выводится из вкладки:
  /// подпись нужна и панели мозаики, а доставать её из виджета вкладки —
  /// значит зависеть от того, каким виджетом её нарисовали.
  final String title;
  final RecordingBloc recordingBloc;
  final RtEegDataBloc rtEegDataBloc;

  late final DeviceEegBridge _eegBridge;
  late final RecordingBridge _recordingBridge;
  late final StreamSubscription<RecordingState> _recordingSub;
  RecordingStatus _lastRecordingStatus = RecordingStatus.idle;

  /// Счётчик пересборки видов графика.
  ///
  /// Настройки фильтров — изменяемый объект, общий с графиком, поэтому по нему
  /// самому перестроиться нельзя: панель фильтров показывала бы старые
  /// значения. Вид слушает счётчик и пересоздаёт график по ключу.
  final ValueNotifier<int> plotSettingsRevision = ValueNotifier(0);

  void _onRecordingState(RecordingState state) {
    if (_lastRecordingStatus == RecordingStatus.preparing &&
        state.status == RecordingStatus.recording) {
      rtEegDataBloc.add(RtEegResetRequested());
      _applyRecordingFiltersToPlot(state.filters);
    }
    _lastRecordingStatus = state.status;
  }

  /// Переносит фильтры, выбранные при старте записи, на живой график.
  ///
  /// Иначе оператор выставляет их дважды: один раз в диалоге старта (для
  /// записи) и второй раз руками в панели (для картинки).
  void _applyRecordingFiltersToPlot(RecordingFilters filters) {
    final plotFilters = rtEegDataBloc.eegSettings.fillterSettings;
    plotFilters.lp = filters.lpHz;
    plotFilters.hp = filters.hpHz;
    plotFilters.notch = filters.notchHz;
    plotFilters.isLpOn = filters.isLpEnabled;
    plotFilters.isHpOn = filters.isHpEnabled;
    plotFilters.isNotchOn = filters.isNotchEnabled;
    rtEegDataBloc.add(NewSettings(newSettings: rtEegDataBloc.eegSettings));
    plotSettingsRevision.value++;
  }

  bool _disposed = false;

  /// Сессию уже отдали на закрытие.
  ///
  /// Отдельный флаг, потому что «закрыта» и «закрыты её bloc'и» — разные
  /// моменты: закрытие асинхронное, а сессию к этому времени уже нельзя
  /// использовать. Он же не даёт закрыть дважды.
  bool get isDisposed => _disposed;

  /// Закрывает только то, чем сессия владеет. `connection.close()` не
  /// вызывается: устройство остаётся подключённым и после закрытия вкладки.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Порядок важен: сначала перекрываем всё, что шлёт события, и **дожидаемся**
    // отмены подписок, потом закрываем получателей. Мосты отменяют подписки
    // асинхронно, и без await пакет, пришедший в этом окне, летел бы в уже
    // закрывающийся bloc — «Cannot add new events after calling close».
    await Future.wait([
      _recordingSub.cancel(),
      _eegBridge.dispose(),
      _recordingBridge.dispose(),
    ]);
    plotSettingsRevision.dispose();
    await recordingBloc.close();
    await rtEegDataBloc.close();
  }
}
