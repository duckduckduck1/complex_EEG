# annotation.md

## Статус

Draft.

Документ описывает реализацию ручной разметки.

---

## BLoC

```text
AnnotationBloc
AnnotationEditorCubit
```

`AnnotationBloc` хранит состояние меток текущего experiment view.
`AnnotationEditorCubit` хранит состояние формы создания/редактирования метки.
Справочник типов меток читается из app-level singleton `LabelDictionaryCubit`.

---

## Types

### State labels

Интервальные состояния:

```text
sleep
rest
eating
grooming
locomotion
custom
```

Список не зашит в код. Он идёт из настраиваемого справочника.

### Point events

Точечные события:

```text
startle
movement
custom_event
```

### Bad/exclude regions

Интервальные метки исключения из анализа.

---

## Coordinate system

Любая метка привязана к:

```text
segment_id
segment_sample_index
```

Интервальная метка:

```text
segment_id
start_segment_sample_index
end_segment_sample_index
```

Правила:

- interval is `[start, end)`;
- interval cannot cross segment boundary;
- point event must be inside segment;
- labels do not create or modify segments.

---

## Live annotation

During recording:

1. user starts state label;
2. app captures current segment/sample index;
3. journal writes `annotation_created` draft/start event;
4. user ends label;
5. journal writes end/update event.

If BLE disconnect happens while state label is open:

- label closes at segment end;
- user may start a new label after reconnect;
- app does not infer behavior during gap.

---

## Saved experiment annotation

User can open saved experiment and add/edit/delete labels.

Rules:

- `signal.bin` is never changed;
- changes write to journal or annotation change log;
- final `experiment.json` is rebuilt atomically;
- edits are validated before saving.

---

## Dictionary

Dictionary record:

```text
label_type_id
kind: state | event | exclude
display_name
color
is_active
sort_order
```

Inactive labels remain readable for old experiments.

---

## UI state

`AnnotationState` includes:

```text
labels
active_draft_label
selected_label_id
validation_error
is_saving
```

Widget does not mutate labels directly.

`AnnotationState` не содержит dictionary. Экран аннотации подписывается на два
источника состояния:

```dart
BlocBuilder<AnnotationBloc, AnnotationState>(...)
BlocBuilder<LabelDictionaryCubit, LabelDictionaryState>(...)
```

`AnnotationBloc` отвечает за метки конкретного эксперимента. App-level
`LabelDictionaryCubit` отвечает за справочник типов меток. Виджет объединяет оба
state только для отображения.

---

## Проверки реализации

- interval label cannot cross segment boundary;
- point event outside segment is rejected;
- disconnect closes open state label;
- saved annotation rebuilds JSON atomically;
- inactive dictionary label still renders old experiments;
- bad/exclude region is stored as annotation, not signal mutation.
