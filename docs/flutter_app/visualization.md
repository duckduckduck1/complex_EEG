# Визуализация (графики)

## Статус

Draft.

Документ описывает реализацию графика live и сохранённого сигнала.

---

## BLoC

```text
VisualizationBloc
SignalBufferCubit
ChartViewportCubit
ExperimentViewerBloc
```

`VisualizationBloc` отвечает за данные графика. Widget отвечает только за
отрисовку.

---

## Live chart

Live chart получает downsampled/windowed signal из memory buffer.

Правила:

- chart does not read `signal.bin` during recording;
- chart updates are throttled;
- writer receives all samples;
- chart may render fewer points than written to disk.

---

## Saved chart

Saved chart reads from `signal.bin` through repository:

```text
ExperimentSignalReader
```

Reader supports:

- read sample range;
- downsample for viewport;
- map global sample index to segment-local index;
- avoid reading across gaps as continuous signal.

---

## Viewport

Viewport state:

```text
start_sample
end_sample
amplitude_min
amplitude_max
zoom_level
follow_live_tail
```

Zoom/pan is BLoC/Cubit state, not widget local state.

---

## Gaps and segments

Chart must show gaps explicitly:

- no line connecting segment end to next segment start;
- gap marker visible;
- labels and ФБМ events render inside segments only.

---

## Overlays

Overlays:

- state labels;
- point events;
- ФБМ events;
- bad/exclude regions;
- disconnect gaps;
- quality warnings.

Overlay data comes from `AnnotationBloc`, `SegmentBloc` and `QualityBloc`.

---

## Performance

Rules:

- never render all samples for long recording;
- use downsampled viewport data;
- cache decoded sample ranges;
- avoid rebuilding entire screen on each packet;
- use `BlocSelector` for chart-only state.

---

## Проверки реализации

- recording remains smooth while disk flush runs;
- chart does not connect across gaps;
- zoom/pan survives widget rebuild;
- annotations align by segment/sample index;
- saved experiment can open without active BLE connection.
