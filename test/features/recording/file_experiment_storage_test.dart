import 'dart:io';

import 'package:eeg_app_max30003_stm32/features/recording/data/file_experiment_storage.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/experiment_folder_name.dart';
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
      folderName: 'exp_race',
    );

    final futures = <Future<void>>[];
    for (var i = 0; i < 50; i++) {
      futures.add(
        storage.appendSamples(filtered: [i, -i], raw: [i * 2, -i * 2]),
      );
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

  test('папка называется именем эксперимента, а не ULID', () async {
    final storage = FileExperimentStorage();
    await storage.createExperiment(
      rootDirectory: root.path,
      experimentId: 'exp_01KXRRWFYXAS309BZ0BX5KQ65Z',
      folderName: 'Мышь 1',
    );
    await storage.close();

    final folder = Directory.fromUri(root.uri.resolve('Мышь%201/'));
    expect(await folder.exists(), isTrue);
    expect(
      await File.fromUri(folder.uri.resolve('signal.bin')).exists(),
      isTrue,
    );
  });

  test('повтор названия отклоняется и не трогает чужие данные', () async {
    final first = FileExperimentStorage();
    await first.createExperiment(
      rootDirectory: root.path,
      experimentId: 'exp_first',
      folderName: 'Мышь 1',
    );
    await first.appendSamples(filtered: [1, 2, 3], raw: [1, 2, 3]);
    await first.close();

    final signal = File.fromUri(root.uri.resolve('Мышь%201/signal.bin'));
    final sizeBefore = await signal.length();
    expect(sizeBefore, 3 * 4);

    final second = FileExperimentStorage();
    await expectLater(
      second.createExperiment(
        rootDirectory: root.path,
        experimentId: 'exp_second',
        folderName: 'Мышь 1',
      ),
      throwsA(isA<ExperimentFolderExists>()),
    );

    // Данные первого эксперимента не затёрты.
    expect(await signal.length(), sizeBefore);
  });

  test('сырой сигнал пишется вторым файлом той же длины', () async {
    final storage = FileExperimentStorage(flushInterval: Duration.zero);
    await storage.createExperiment(
      rootDirectory: root.path,
      experimentId: '01KXTF74CQSD65FWE0S2DF1WWZ',
      folderName: 'Мышь 1',
    );
    // Фильтр меняет значения, но количество отсчётов совпадает.
    await storage.appendSamples(filtered: [10, 20, 30], raw: [11, 21, 31]);
    await storage.close();

    final folder = root.uri.resolve('Мышь%201/');
    final signal = File.fromUri(folder.resolve('signal.bin'));
    final rawSignal = File.fromUri(folder.resolve('signal_raw.bin'));

    expect(await rawSignal.exists(), isTrue);
    expect(await signal.length(), 3 * 4);
    expect(
      await rawSignal.length(),
      await signal.length(),
      reason: 'по индексу отсчёта оба файла должны совпадать',
    );

    // Содержимое разное: фильтрованный не равен сырому.
    expect(await signal.readAsBytes(), isNot(await rawSignal.readAsBytes()));
  });

  test('close дожидается записи и закрывает файл без гонки', () async {
    final storage = FileExperimentStorage(flushInterval: Duration.zero);
    await storage.createExperiment(
      rootDirectory: root.path,
      experimentId: 'exp_close',
      folderName: 'exp_close',
    );

    // append и close «одновременно»: close должен встать в очередь после append.
    final append = storage.appendSamples(filtered: [1, 2, 3], raw: [1, 2, 3]);
    final close = storage.close();
    await Future.wait([append, close]);

    final signal = File.fromUri(root.uri.resolve('exp_close/signal.bin'));
    expect(await signal.length(), 3 * 4);
  });
}
