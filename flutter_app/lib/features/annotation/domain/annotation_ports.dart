abstract interface class AnnotationClock {
  DateTime now();
}

abstract interface class AnnotationIdGenerator {
  String nextId();
}

abstract interface class AnnotationJournal {
  Future<void> appendAnnotation(
    Map<String, Object?> event, {
    bool flush = true,
  });
}

class SystemAnnotationClock implements AnnotationClock {
  const SystemAnnotationClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
