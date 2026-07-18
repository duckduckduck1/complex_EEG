import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eeg_app_max30003_stm32/features/recording/domain/experiment_folder_name.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

/// Пишет пакет эксперимента в папку на диске оператора.
///
/// Раскладка: `signal.bin` (отсчёты int32 little-endian), `journal.ndjson`
/// (append-only журнал) и финальный `experiment.json`.
///
/// Сигнал буферизуется и сбрасывается пачками, чтобы не дёргать диск на каждый
/// отсчёт при 250 Гц; критичные события журнала пишутся с немедленным flush.
/// `experiment.json` собирается один раз при остановке и пишется атомарно —
/// через временный файл и переименование.
///
/// Операции с `signal.bin` идут через очередь ([_synchronized]): `RandomAccessFile`
/// не допускает двух одновременных async-операций, а `RecordingBloc` по умолчанию
/// обрабатывает события конкурентно, поэтому flush из приёма отсчётов мог
/// наложиться на flush из остановки/обрыва («async operation is currently
/// pending»). Очередь сериализует записи независимо от порядка вызовов.
class FileExperimentStorage implements ExperimentStorage {
  FileExperimentStorage({this.flushInterval = const Duration(seconds: 10)});

  final Duration flushInterval;

  Directory? _experimentDirectory;
  RandomAccessFile? _signalFile;
  RandomAccessFile? _rawSignalFile;
  IOSink? _journalSink;
  final List<int> _pendingSamples = <int>[];
  final List<int> _pendingRawSamples = <int>[];
  DateTime _lastSignalFlush = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _fileQueue = Future<void>.value();

  /// Ставит [action] в очередь файловых операций: следующая ждёт завершения
  /// предыдущей (успех или ошибка), поэтому две записи в `signal.bin` никогда
  /// не идут одновременно.
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _fileQueue = _fileQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
    required String folderName,
  }) async {
    await close();

    final root = Directory(rootDirectory);
    final experimentDirectory = Directory(
      '${root.path}${Platform.pathSeparator}$folderName',
    );
    // Не дописываем в чужую папку: иначе перемешаем два эксперимента и затрём
    // signal.bin уже записанного.
    if (await experimentDirectory.exists()) {
      throw ExperimentFolderExists(folderName);
    }
    await experimentDirectory.create(recursive: true);

    final signalFile = File.fromUri(
      experimentDirectory.uri.resolve('signal.bin'),
    );
    final rawSignalFile = File.fromUri(
      experimentDirectory.uri.resolve('signal_raw.bin'),
    );
    final journalFile = File.fromUri(
      experimentDirectory.uri.resolve('journal.ndjson'),
    );

    _experimentDirectory = experimentDirectory;
    _signalFile = await signalFile.open(mode: FileMode.write);
    _rawSignalFile = await rawSignalFile.open(mode: FileMode.write);
    await journalFile.writeAsString('', encoding: utf8);
    _journalSink = journalFile.openWrite(mode: FileMode.append, encoding: utf8);
    _lastSignalFlush = DateTime.now().toUtc();
  }

  @override
  Future<void> appendSamples({
    required List<int> filtered,
    required List<int> raw,
  }) async {
    _ensureOpen();
    _pendingSamples.addAll(filtered);
    _pendingRawSamples.addAll(raw);

    final now = DateTime.now().toUtc();
    if (now.difference(_lastSignalFlush) >= flushInterval) {
      await flush();
    }
  }

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {
    final journalSink = _journalSink;
    if (journalSink == null) {
      throw StateError('Experiment storage is not opened');
    }

    journalSink.writeln(jsonEncode(event));
    if (flush) {
      await journalSink.flush();
    }
  }

  @override
  Future<void> flush() => _synchronized(_flushLocked);

  Future<void> _flushLocked() async {
    final signalFile = _signalFile;
    if (signalFile == null) {
      return;
    }

    if (_pendingSamples.isNotEmpty) {
      final bytes = _encodeSamples(_pendingSamples);
      _pendingSamples.clear();
      await signalFile.writeFrom(bytes);
    }
    await signalFile.flush();

    final rawSignalFile = _rawSignalFile;
    if (rawSignalFile != null) {
      if (_pendingRawSamples.isNotEmpty) {
        final rawBytes = _encodeSamples(_pendingRawSamples);
        _pendingRawSamples.clear();
        await rawSignalFile.writeFrom(rawBytes);
      }
      await rawSignalFile.flush();
    }

    await _journalSink?.flush();
    _lastSignalFlush = DateTime.now().toUtc();
  }

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {
    final experimentDirectory = _experimentDirectory;
    if (experimentDirectory == null) {
      throw StateError('Experiment storage is not opened');
    }

    final target = File.fromUri(
      experimentDirectory.uri.resolve('experiment.json'),
    );
    final temp = File.fromUri(
      experimentDirectory.uri.resolve('experiment.json.tmp'),
    );
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(encoder.convert(experimentJson), encoding: utf8);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }

  @override
  Future<void> close() async {
    // Дозаписать хвост и закрыть хендлы в той же очереди, чтобы закрытие не
    // наложилось на незавершённый flush из потока отсчётов.
    await _synchronized(() async {
      await _flushLocked();
      await _signalFile?.close();
      await _rawSignalFile?.close();
      await _journalSink?.flush();
      await _journalSink?.close();
      _signalFile = null;
      _rawSignalFile = null;
      _journalSink = null;
      _experimentDirectory = null;
      _pendingSamples.clear();
      _pendingRawSamples.clear();
    });
  }

  void _ensureOpen() {
    if (_signalFile == null) {
      throw StateError('Experiment storage is not opened');
    }
  }

  List<int> _encodeSamples(List<int> samples) {
    final bytes = ByteData(samples.length * 4);
    for (var index = 0; index < samples.length; index++) {
      bytes.setInt32(index * 4, samples[index], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
