import 'dart:io';

import 'package:eeg_app_max30003_stm32/features/recording/data/file_experiment_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('eeg_storage_test');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('одновременные append и flush не роняют signal.bin', () async {
    // flushInterval=0 — каждый append пытается сбросить буфер, поэтому без
    // сериализации две async-операции на RandomAccessFile наложились бы и
    // бросили «async operation is currently pending».
    final storage = FileExperimentStorage(flushInterval: Duration.zero);
    await storage.createExperiment(
      rootDirectory: root.path,
      experimentId: 'exp_race',
    );

    final futures = <Future<void>>[];
    for (var i = 0; i < 50; i++) {
      futures.add(storage.appendSamples([i, -i]));
    }
    futures.add(storage.flush());

    // Не должно бросить.
    await Future.wait(futures);
    await storage.close();

    final signal = File.fromUri(root.uri.resolve('exp_race/signal.bin'));
    expect(await signal.exists(), isTrue);
    // 50 пачек по 2 отсчёта × 4 байта (int32).
    expect(await signal.length(), 50 * 2 * 4);
  });

  test('close дожидается записи и закрывает файл без гонки', () async {
    final storage = FileExperimentStorage(flushInterval: Duration.zero);
    await storage.createExperiment(
      rootDirectory: root.path,
      experimentId: 'exp_close',
    );

    // append и close «одновременно»: close должен встать в очередь после append.
    final append = storage.appendSamples([1, 2, 3]);
    final close = storage.close();
    await Future.wait([append, close]);

    final signal = File.fromUri(root.uri.resolve('exp_close/signal.bin'));
    expect(await signal.length(), 3 * 4);
  });
}
