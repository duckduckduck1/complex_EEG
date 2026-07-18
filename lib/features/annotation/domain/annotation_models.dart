import 'package:equatable/equatable.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';

/// Вид метки.
///
/// - [state] — состояние животного, **интервал**: открывается и обязана быть
///   закрыта. Одновременно открыта может быть только одна. Такую же метку можно
///   поставить вручную интервалом по времени.
/// - [event] — точечное событие, мгновенная отметка на одном отсчёте.
/// - [exclude] — интервал-исключение из анализа: «Артефакт сигнала». Ставится
///   вручную по времени, когда плохой участок длится, а не случается мгновенно.
///
/// Словарь меток — про наблюдаемое поведение (спит, ест, бегает), а не про
/// стадии сна: оператор биолог или студент и по сигналу их не поставит.
enum AnnotationKind { state, event, exclude }

class LabelType extends Equatable {
  const LabelType({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.colorHex,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final AnnotationKind kind;
  final String displayName;
  final String colorHex;
  final bool isActive;
  final int sortOrder;

  @override
  List<Object?> get props => [
    id,
    kind,
    displayName,
    colorHex,
    isActive,
    sortOrder,
  ];
}

/// Словарь меток по умолчанию — про наблюдаемое поведение мыши, не про стадии
/// сна. Оператор биолог или студент: по сигналу стадию он не поставит, а что
/// зверёк делает в клетке — опишет надёжно. Скоринг сна по ЭЭГ — задача
/// постобработки, не оператора.
///
/// Состояния (интервалы) идут в порядке `sortOrder` — так же они лягут в
/// выкатывающемся списке; события (точки) и брак — отдельными группами.
const defaultLabelTypes = <LabelType>[
  LabelType(
    id: 'sleep',
    kind: AnnotationKind.state,
    displayName: 'Спит',
    colorHex: '#9B7CFF',
    sortOrder: 10,
  ),
  LabelType(
    id: 'settling',
    kind: AnnotationKind.state,
    displayName: 'Пытается уснуть',
    colorHex: '#6EA8FF',
    sortOrder: 20,
  ),
  LabelType(
    id: 'sitting',
    kind: AnnotationKind.state,
    displayName: 'Сидит',
    colorHex: '#38BDF8',
    sortOrder: 30,
  ),
  LabelType(
    id: 'running',
    kind: AnnotationKind.state,
    displayName: 'Бегает',
    colorHex: '#2EE6C8',
    sortOrder: 40,
  ),
  LabelType(
    id: 'exploring',
    kind: AnnotationKind.state,
    displayName: 'Исследует',
    colorHex: '#22C55E',
    sortOrder: 50,
  ),
  LabelType(
    id: 'eating',
    kind: AnnotationKind.state,
    displayName: 'Ест',
    colorHex: '#EAB308',
    sortOrder: 60,
  ),
  LabelType(
    id: 'drinking',
    kind: AnnotationKind.state,
    displayName: 'Пьёт',
    colorHex: '#F59E0B',
    sortOrder: 70,
  ),
  LabelType(
    id: 'grooming',
    kind: AnnotationKind.state,
    displayName: 'Умывается',
    colorHex: '#A855F7',
    sortOrder: 80,
  ),
  LabelType(
    id: 'nesting',
    kind: AnnotationKind.state,
    displayName: 'Роет / гнездо',
    colorHex: '#94A3B8',
    sortOrder: 90,
  ),
  LabelType(
    id: 'freezing',
    kind: AnnotationKind.state,
    displayName: 'Замерла',
    colorHex: '#F97316',
    sortOrder: 100,
  ),
  LabelType(
    id: 'agitated',
    kind: AnnotationKind.state,
    displayName: 'Беспокоится',
    colorHex: '#FF5C6C',
    sortOrder: 110,
  ),
  LabelType(
    id: 'custom',
    kind: AnnotationKind.state,
    displayName: 'Своё состояние',
    colorHex: '#CBD5E1',
    sortOrder: 120,
  ),
  LabelType(
    id: 'woke_up',
    kind: AnnotationKind.event,
    displayName: 'Проснулась',
    colorHex: '#FACC15',
    sortOrder: 210,
  ),
  LabelType(
    id: 'startle',
    kind: AnnotationKind.event,
    displayName: 'Вздрогнула',
    colorHex: '#FB7185',
    sortOrder: 220,
  ),
  LabelType(
    id: 'twitch',
    kind: AnnotationKind.event,
    displayName: 'Дёрнулась',
    colorHex: '#38BDF8',
    sortOrder: 230,
  ),
  LabelType(
    id: 'external_noise',
    kind: AnnotationKind.event,
    displayName: 'Внешний шум',
    colorHex: '#F59E0B',
    sortOrder: 240,
  ),
  LabelType(
    id: 'cage_touched',
    kind: AnnotationKind.event,
    displayName: 'Трогали клетку',
    colorHex: '#C084FC',
    sortOrder: 250,
  ),
  LabelType(
    id: 'custom_event',
    kind: AnnotationKind.event,
    displayName: 'Своя отметка',
    colorHex: '#CBD5E1',
    sortOrder: 260,
  ),
  // Артефакты сигнала: отмечают, ПОЧЕМУ на записи скачок — чтобы тот, кто будет
  // разбирать данные, не гадал. Идут в конце списка событий.
  LabelType(
    id: 'wire_touched',
    kind: AnnotationKind.event,
    displayName: 'Задели провод',
    colorHex: '#F43F5E',
    sortOrder: 310,
  ),
  LabelType(
    id: 'sensor_hit',
    kind: AnnotationKind.event,
    displayName: 'Ударилась датчиком',
    colorHex: '#FB7185',
    sortOrder: 320,
  ),
  LabelType(
    id: 'electrode_moved',
    kind: AnnotationKind.event,
    displayName: 'Сместился электрод',
    colorHex: '#E879F9',
    sortOrder: 330,
  ),
  LabelType(
    id: 'interference',
    kind: AnnotationKind.event,
    displayName: 'Наводка / помеха',
    colorHex: '#FDBA74',
    sortOrder: 340,
  ),
  // Затяжной артефакт — интервалом: ставится вручную по времени, когда плохой
  // участок длится, а не случается мгновенно.
  LabelType(
    id: 'artifact',
    kind: AnnotationKind.exclude,
    displayName: 'Артефакт сигнала',
    colorHex: '#F43F5E',
    sortOrder: 410,
  ),
];

class AnnotationPoint extends Equatable {
  const AnnotationPoint({
    required this.segmentId,
    required this.segmentStartSample,
    required this.segmentEndSample,
    required this.segmentSampleIndex,
    required this.wallClockTime,
  });

  final String segmentId;
  final int segmentStartSample;
  final int segmentEndSample;
  final int segmentSampleIndex;
  final DateTime wallClockTime;

  int get globalSampleIndex => segmentStartSample + segmentSampleIndex;

  @override
  List<Object?> get props => [
    segmentId,
    segmentStartSample,
    segmentSampleIndex,
    wallClockTime,
    segmentEndSample,
  ];
}

/// Метка эксперимента.
///
/// Координаты хранятся дважды: [segmentId] + `*SegmentSampleIndex` — позиция
/// внутри сегмента (метка обязана целиком лежать в своём сегменте), и
/// `global*SampleIndex` — индекс в `signal.bin`, чтобы пост-анализ не собирал
/// его сам. Интервал полуоткрытый: `[start, end)`.
///
/// [isDraft] — состояние открыто, но ещё не закрыто. Черновики в
/// `experiment.json` не попадают: незакрытый интервал не пакет.
class AnnotationLabel extends Equatable {
  const AnnotationLabel({
    required this.id,
    required this.kind,
    required this.labelTypeId,
    required this.segmentId,
    required this.startSegmentSampleIndex,
    required this.globalStartSampleIndex,
    required this.startedAtWallClock,
    this.endSegmentSampleIndex,
    this.globalEndSampleIndex,
    this.endedAtWallClock,
    this.note,
    this.isDraft = false,
  });

  final String id;
  final AnnotationKind kind;
  final String labelTypeId;
  final String segmentId;
  final int startSegmentSampleIndex;
  final int globalStartSampleIndex;
  final DateTime startedAtWallClock;
  final int? endSegmentSampleIndex;
  final int? globalEndSampleIndex;
  final DateTime? endedAtWallClock;
  final String? note;
  final bool isDraft;

  bool get isPoint => kind == AnnotationKind.event;

  AnnotationLabel closeAt(AnnotationPoint end) {
    return copyWith(
      endSegmentSampleIndex: end.segmentSampleIndex,
      globalEndSampleIndex: end.globalSampleIndex,
      endedAtWallClock: end.wallClockTime,
      isDraft: false,
    );
  }

  AnnotationLabel copyWith({
    int? endSegmentSampleIndex,
    int? globalEndSampleIndex,
    DateTime? endedAtWallClock,
    bool? isDraft,
  }) {
    return AnnotationLabel(
      id: id,
      kind: kind,
      labelTypeId: labelTypeId,
      segmentId: segmentId,
      startSegmentSampleIndex: startSegmentSampleIndex,
      globalStartSampleIndex: globalStartSampleIndex,
      startedAtWallClock: startedAtWallClock,
      endSegmentSampleIndex:
          endSegmentSampleIndex ?? this.endSegmentSampleIndex,
      globalEndSampleIndex: globalEndSampleIndex ?? this.globalEndSampleIndex,
      endedAtWallClock: endedAtWallClock ?? this.endedAtWallClock,
      note: note,
      isDraft: isDraft ?? this.isDraft,
    );
  }

  Map<String, Object?> toJournalJson() {
    final json = <String, Object?>{
      'label_id': id,
      'kind': kind.name,
      'label_type_id': labelTypeId,
      'segment_id': segmentId,
      if (note != null && note!.trim().isNotEmpty) 'note': note,
    };

    // Время в чч:мм:сс дублирует индексы отсчётов, а не заменяет их: индексы
    // нужны машине, время — человеку, который открыл json глазами.
    if (isPoint) {
      json.addAll({
        'sample_index': globalStartSampleIndex,
        'segment_sample_index': startSegmentSampleIndex,
        'global_sample_index': globalStartSampleIndex,
        'time': formatClockFromSamples(globalStartSampleIndex),
        'wall_clock_time': startedAtWallClock.toUtc().toIso8601String(),
      });
    } else {
      json.addAll({
        'start_sample': globalStartSampleIndex,
        if (globalEndSampleIndex != null) 'end_sample': globalEndSampleIndex,
        'start_segment_sample_index': startSegmentSampleIndex,
        if (endSegmentSampleIndex != null)
          'end_segment_sample_index': endSegmentSampleIndex,
        'start_time': formatClockFromSamples(globalStartSampleIndex),
        if (globalEndSampleIndex != null)
          'end_time': formatClockFromSamples(globalEndSampleIndex!),
        if (globalEndSampleIndex != null)
          'duration': formatClockFromSamples(
            globalEndSampleIndex! - globalStartSampleIndex,
          ),
        'started_at_wall_clock': startedAtWallClock.toUtc().toIso8601String(),
        if (endedAtWallClock != null)
          'ended_at_wall_clock': endedAtWallClock!.toUtc().toIso8601String(),
        if (isDraft) 'draft': true,
      });
    }

    return json;
  }

  Map<String, Object?> toExperimentJson() {
    if (!isPoint &&
        (endSegmentSampleIndex == null || globalEndSampleIndex == null)) {
      throw StateError('Draft interval label cannot be written to experiment');
    }
    final json = toJournalJson()..remove('draft');
    return json;
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    labelTypeId,
    segmentId,
    startSegmentSampleIndex,
    globalStartSampleIndex,
    startedAtWallClock,
    endSegmentSampleIndex,
    globalEndSampleIndex,
    endedAtWallClock,
    note,
    isDraft,
  ];
}
