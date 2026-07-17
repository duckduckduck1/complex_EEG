import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';

class FileExperimentStorage implements ExperimentStorage {
  FileExperimentStorage({this.flushInterval = const Duration(seconds: 10)});

  final Duration flushInterval;

  Directory? _experimentDirectory;
  RandomAccessFile? _signalFile;
  IOSink? _journalSink;
  final List<int> _pendingSamples = <int>[];
  DateTime _lastSignalFlush = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
  }) async {
    await close();

    final root = Directory(rootDirectory);
    final experimentDirectory = Directory.fromUri(
      root.uri.resolve('$experimentId/'),
    );
    await experimentDirectory.create(recursive: true);

    final signalFile = File.fromUri(
      experimentDirectory.uri.resolve('signal.bin'),
    );
    final journalFile = File.fromUri(
      experimentDirectory.uri.resolve('journal.ndjson'),
    );

    _experimentDirectory = experimentDirectory;
    _signalFile = await signalFile.open(mode: FileMode.write);
    await journalFile.writeAsString('', encoding: utf8);
    _journalSink = journalFile.openWrite(mode: FileMode.append, encoding: utf8);
    _lastSignalFlush = DateTime.now().toUtc();
  }

  @override
  Future<void> appendSamples(List<int> samples) async {
    _ensureOpen();
    _pendingSamples.addAll(samples);

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
  Future<void> flush() async {
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
    await flush();
    await _signalFile?.close();
    await _journalSink?.flush();
    await _journalSink?.close();
    _signalFile = null;
    _journalSink = null;
    _experimentDirectory = null;
    _pendingSamples.clear();
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
