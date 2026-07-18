import 'dart:async';

import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';

/// Обёртка над [BleConnection], которая считает связь разорванной, если поток
/// отсчётов замолчал.
///
/// Зачем: платформа не всегда сообщает об обрыве. На Windows `onDisconnected`
/// может не сработать вовсе — статус остаётся `connected`, а данные просто
/// перестают идти. Тогда рушится вся цепочка: запись не встаёт на паузу,
/// кнопка переподключения инертна (она работает только из `lost`/`failed`), а
/// после возврата связи не открывается новый сегмент.
///
/// Устройство стримит непрерывно (250 Гц), поэтому длительная тишина — надёжный
/// признак мёртвой связи независимо от платформы. [onDisconnected] завершается
/// по любому из двух признаков: платформа сообщила об обрыве **или** отсчётов не
/// было дольше [silenceTimeout].
///
/// Таймер взводится только после первого отсчёта: пока поток не пошёл, тишина
/// ещё ничего не значит — иначе ложный обрыв на этапе подключения.
class LivenessCheckedConnection implements BleConnection {
  LivenessCheckedConnection(
    this._inner, {
    this.silenceTimeout = const Duration(seconds: 5),
  }) {
    _inner.onDisconnected.then((_) => _markDisconnected());
  }

  final BleConnection _inner;
  final Duration silenceTimeout;

  final Completer<void> _disconnected = Completer<void>();
  Timer? _silenceTimer;

  @override
  Stream<List<int>> get packets {
    return _inner.packets.map((payload) {
      _rearmSilenceTimer();
      return payload;
    });
  }

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> writeCommand(List<int> frame) => _inner.writeCommand(frame);

  @override
  Future<void> disconnect() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    await _inner.disconnect();
    _markDisconnected();
  }

  void _rearmSilenceTimer() {
    if (_disconnected.isCompleted) {
      return;
    }
    _silenceTimer?.cancel();
    _silenceTimer = Timer(silenceTimeout, _markDisconnected);
  }

  void _markDisconnected() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
  }
}
