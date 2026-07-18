import 'dart:async';

import 'package:eeg_app_max30003_stm32/features/devices/data/liveness_checked_connection.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _InnerConnection implements BleConnection {
  final StreamController<List<int>> _packets =
      StreamController<List<int>>.broadcast();
  final Completer<void> _disconnected = Completer<void>();
  final List<List<int>> commands = <List<int>>[];
  bool disconnectCalled = false;

  @override
  Stream<List<int>> get packets => _packets.stream;

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> writeCommand(List<int> frame) async => commands.add(frame);

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  void addPayload(List<int> payload) => _packets.add(payload);

  /// Обрыв, о котором платформа СООБЩИЛА.
  void reportDisconnect() {
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  Future<void> close() => _packets.close();
}

void main() {
  late _InnerConnection inner;

  setUp(() => inner = _InnerConnection());
  tearDown(() => inner.close());

  test(
    'молчащий поток завершает onDisconnected, даже если платформа молчит',
    () async {
      final connection = LivenessCheckedConnection(
        inner,
        silenceTimeout: const Duration(milliseconds: 40),
      );
      var disconnected = false;
      unawaited(connection.onDisconnected.then((_) => disconnected = true));

      // Слушателя нужно завести: сторож взводится на отсчётах.
      final sub = connection.packets.listen((_) {});
      addTearDown(sub.cancel);

      inner.addPayload([1, 2, 3]);
      await pumpEventQueue();
      expect(disconnected, isFalse, reason: 'данные только что шли');

      // Поток замолчал; inner.onDisconnected при этом НЕ завершается.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await pumpEventQueue();

      expect(disconnected, isTrue);
    },
  );

  test('идущий поток не даёт ложного обрыва', () async {
    final connection = LivenessCheckedConnection(
      inner,
      silenceTimeout: const Duration(milliseconds: 80),
    );
    var disconnected = false;
    unawaited(connection.onDisconnected.then((_) => disconnected = true));

    final sub = connection.packets.listen((_) {});
    addTearDown(sub.cancel);

    for (var i = 0; i < 5; i++) {
      inner.addPayload([i]);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(disconnected, isFalse);
  });

  test('обрыв от платформы завершает onDisconnected сразу', () async {
    final connection = LivenessCheckedConnection(
      inner,
      silenceTimeout: const Duration(seconds: 30),
    );
    var disconnected = false;
    unawaited(connection.onDisconnected.then((_) => disconnected = true));

    inner.reportDisconnect();
    await pumpEventQueue();

    expect(disconnected, isTrue);
  });

  test(
    'без отсчётов сторож не взводится и ложный обрыв не срабатывает',
    () async {
      final connection = LivenessCheckedConnection(
        inner,
        silenceTimeout: const Duration(milliseconds: 30),
      );
      var disconnected = false;
      unawaited(connection.onDisconnected.then((_) => disconnected = true));

      final sub = connection.packets.listen((_) {});
      addTearDown(sub.cancel);

      // Отсчётов не было вообще — этап подключения, тишина ещё ничего не значит.
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await pumpEventQueue();

      expect(disconnected, isFalse);
    },
  );

  test('команды и disconnect проходят во внутреннее соединение', () async {
    final connection = LivenessCheckedConnection(inner);

    await connection.writeCommand([1, 0, 13, 10]);
    expect(inner.commands.single, [1, 0, 13, 10]);

    await connection.disconnect();
    expect(inner.disconnectCalled, isTrue);
    await expectLater(connection.onDisconnected, completes);
  });
}
