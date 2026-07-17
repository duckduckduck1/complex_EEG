import 'recording_models.dart';

/// Куда уезжает эксперимент: папка на диске оператора.
///
/// Порт скрывает файловую систему, поэтому запись тестируется на хранилище
/// в памяти. Раскладка папки и формат файлов описаны в README.
abstract interface class ExperimentStorage {
  /// Создать папку эксперимента `exp_<ULID>` внутри [rootDirectory].
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
  });

  /// Дописать отсчёты в `signal.bin` (int32 little-endian, микровольты).
  ///
  /// Только append: уже записанное не переписывается никогда.
  Future<void> appendSamples(List<int> samples);

  /// Дописать событие в `journal.ndjson` (append-only, одна JSON-строка).
  ///
  /// [flush] для критичных событий (границы сегментов, обрыв, ФБМ, метки):
  /// их нельзя потерять при внезапном завершении.
  Future<void> appendJournal(Map<String, Object?> event, {bool flush = false});

  Future<void> flush();

  /// Записать финальный `experiment.json` **атомарно** — через временный файл
  /// и переименование, чтобы недописанный JSON не выдавался за готовый пакет.
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson);

  Future<void> close();
}

/// Фильтр записи: обрабатывает поток **по одному отсчёту**, сохраняя состояние
/// между вызовами.
///
/// Это не то же самое, что фильтр графика: тот перефильтровывает весь буфер
/// целиком и для записи непригоден.
abstract interface class StreamingFilter {
  int filter(int sampleMicrovolts);
}

abstract interface class StreamingFilterFactory {
  StreamingFilter create(RecordingFilters filters);
}

/// Часы за портом, чтобы тесты сегментов и разрывов были детерминированными.
abstract interface class RecordingClock {
  DateTime now();
}

abstract interface class ExperimentIdGenerator {
  String nextId();
}

/// Отправка команды ФБМ на устройство.
///
/// Кадр строится в data-слое; сюда приходит уже посчитанный [pwmByte]
/// (см. `RecordingBloc.pwmByteFromLevel`). Возвращает `false`, если команду
/// доставить не удалось — например, соединение уже разорвано.
abstract interface class FbmTransport {
  Future<bool> setLed({required bool on, required int pwmByte});
}

class PassThroughStreamingFilter implements StreamingFilter {
  const PassThroughStreamingFilter();

  @override
  int filter(int sampleMicrovolts) => sampleMicrovolts;
}

class PassThroughStreamingFilterFactory implements StreamingFilterFactory {
  const PassThroughStreamingFilterFactory();

  @override
  StreamingFilter create(RecordingFilters filters) =>
      const PassThroughStreamingFilter();
}

class SystemRecordingClock implements RecordingClock {
  const SystemRecordingClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
