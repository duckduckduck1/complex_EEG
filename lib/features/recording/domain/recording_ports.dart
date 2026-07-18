import 'recording_models.dart';

/// Куда уезжает эксперимент: папка на диске оператора.
///
/// Порт скрывает файловую систему, поэтому запись тестируется на хранилище
/// в памяти. Раскладка папки и формат файлов описаны в README.
abstract interface class ExperimentStorage {
  /// Создать папку эксперимента [folderName] внутри [rootDirectory].
  ///
  /// Папка называется так же, как эксперимент («Мышь 1»), чтобы оператор сразу
  /// понимал, где чьи данные; [experimentId] остаётся машинным ULID и живёт
  /// только в `experiment.json`. Если папка уже есть — бросает
  /// [ExperimentFolderExists], чтобы не смешать два эксперимента.
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
    required String folderName,
  });

  /// Дописать отсчёты: [filtered] в `signal.bin`, [raw] в `signal_raw.bin`
  /// (оба — int32 little-endian, микровольты).
  ///
  /// Пишутся парой и одной длины: по индексу отсчёта из одного файла можно
  /// смотреть тот же отсчёт в другом. Фильтр необратим, поэтому сырой сигнал
  /// сохраняем — по нему можно перефильтровать иначе.
  ///
  /// Только append: уже записанное не переписывается никогда.
  Future<void> appendSamples({
    required List<int> filtered,
    required List<int> raw,
  });

  /// Дописать событие в `journal.ndjson` (append-only, одна JSON-строка).
  ///
  /// [flush] для критичных событий (границы сегментов, обрыв, ФБМ, метки):
  /// их нельзя потерять при внезапном завершении.
  Future<void> appendJournal(Map<String, Object?> event, {bool flush = false});

  Future<void> flush();

  /// Записать `readme.txt` в папку эксперимента — пояснение для того, кому
  /// потом передадут данные.
  Future<void> writeReadme(String text);

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
