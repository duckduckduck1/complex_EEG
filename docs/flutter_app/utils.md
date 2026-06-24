# Утилиты

Документ описывает реализацию диагностических утилит: спектр, мощность по
диапазонам, спектрограмма, предпросмотр фильтров и технические логи.

---

## BLoC

```text
UtilitiesBloc
SpectrumCubit
BandPowerCubit
SpectrogramCubit
FilterPreviewCubit
DiagnosticLogCubit
```

Каждая утилита имеет собственный Cubit или отдельную ветку `UtilitiesBloc`.
Параметры утилит не хранятся в widget state.

`UtilitiesBloc` владеет выбором активной утилиты, выбранным окном анализа и
общими ошибками. Sub-cubits отвечают за конкретные расчёты и параметры.

---

## Events

`UtilitiesBloc` events:

```text
UtilityTabSelected
UtilityWindowChanged
UtilitySegmentChanged
UtilityRefreshRequested
UtilityInputInvalidated
```

Sub-cubit events/actions:

```text
SpectrumParametersChanged
SpectrumCalculationRequested
BandPowerConfigChanged
BandPowerCalculationRequested
SpectrogramParametersChanged
SpectrogramCalculationRequested
FilterPreviewParametersChanged
FilterPreviewResetRequested
DiagnosticLogReloadRequested
```

Widget dispatches events only. DSP calculation is performed by services called
from BLoC/Cubit.

---

## State

`UtilitiesState`:

```text
active_utility
experiment_id
segment_id
window_start_segment_sample_index
window_end_segment_sample_index
is_input_valid
warning
last_error
```

`SpectrumState`:

```text
parameters
is_calculating
frequencies_hz
power
error
```

`BandPowerState`:

```text
bands
selected_window
results
is_calculating
error
```

`SpectrogramState`:

```text
parameters
tiles_or_matrix
missing_data_ranges
is_calculating
error
```

`FilterPreviewState`:

```text
filter_type
parameters
preview_samples
is_calculating
error
```

`DiagnosticLogState`:

```text
entries
filter
is_loading
error
```

---

## Data flow

```text
Visualization/ExperimentViewer selection
  -> UtilitiesBloc UtilityWindowChanged
  -> ExperimentSignalReader reads selected continuous window
  -> DspService calculates spectrum/bands/spectrogram/filter preview
  -> sub-cubit emits result state
  -> widget renders result
```

`ExperimentSignalReader` reads only selected sample ranges. Utilities never load
the full `signal.bin` unless the selected window is the full file by explicit
user action.

---

## Общие правила

- утилиты не изменяют `signal.bin`;
- расчёты выполняются по непрерывным сегментам;
- gaps не заполняются;
- results are diagnostic, not source of truth;
- автоматическая классификация фаз сна не выполняется.

---

## Input window

Utility input:

```text
experiment_id
segment_id
start_segment_sample_index
end_segment_sample_index
sample_rate_hz
samples_microvolts
```

Если окно пересекает gap, UI требует выбрать непрерывный участок или анализирует
только валидную часть с явным warning.

---

## Frequency spectrum

Parameters:

```text
window_seconds
window_function
frequency_min
frequency_max
```

Output:

```text
frequencies_hz[]
power[]
```

Алгоритм:

- к выбранному окну применяется оконная функция (по умолчанию Hann), чтобы
  снизить спектральные утечки;
- длина FFT — степень двойки, покрывающая `window_seconds` при 250 Гц;
- амплитудный спектр нормируется на длину окна и выдаётся в дБ
  (`20 * log10(|X| / N)`);
- частоты считаются до Найквиста (125 Гц) и обрезаются до
  `[frequency_min, frequency_max]` для отображения.

---

## Band power

Band config is user/lab configurable:

```text
band_id
display_name
frequency_from_hz
frequency_to_hz
color
```

Output:

```text
band_id
power
window_start_sample
window_end_sample
```

Мощность полосы — относительная: внутри каждой полосы спектр суммируется в
линейной шкале (из дБ обратно в линейную), затем каждая полоса делится на сумму
по всем настроенным полосам. Результат — доля `0..1`, удобная для сравнения
полос между собой.

Band power does not assign sleep phase. Автоматическое управление ФБМ по порогам
band power в MVP не выполняется — ФБМ включает оператор (см.
[`ble.md`](ble.md)).

---

## Spectrogram

Parameters:

```text
window_seconds
step_seconds
frequency_min
frequency_max
color_scale
```

Spectrogram shows gaps as missing data, not interpolated image.

---

## Filter preview

Supported first-stage previews:

```text
notch
band_pass
high_pass
low_pass
```

Фильтры реализуются как IIR Butterworth: high-pass и low-pass — низких порядков,
notch — band-stop. Частоты среза и порядок — параметры предпросмотра, задаются
пользователем. Фильтр применяется к копии выбранного окна.

Filter preview returns display samples only. No filtered output is written back to
experiment source. `signal.bin` всегда хранит исходные (нефильтрованные) мкВ.

---

## Diagnostic logs

`DiagnosticLogCubit` reads `app.log` and presents:

- time;
- severity;
- subsystem;
- message;
- optional error code.

Logs are for diagnostics and can be included in the experiment package as
`app.log`.

---

## Проверки реализации

- utility cannot write to `signal.bin`;
- analysis window cannot silently cross gap;
- changing filter parameters affects preview only;
- band config is editable without code changes;
- log viewer does not parse `journal.ndjson` as technical log.
