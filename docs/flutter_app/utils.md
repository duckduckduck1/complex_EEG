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
Параметры утилит не хранятся в состоянии виджета.

`UtilitiesBloc` владеет выбором активной утилиты, выбранным окном анализа и
общими ошибками. Sub-cubits отвечают за конкретные расчёты и параметры.

---

## События

События `UtilitiesBloc`:

```text
UtilityTabSelected
UtilityWindowChanged
UtilitySegmentChanged
UtilityRefreshRequested
UtilityInputInvalidated
```

События/действия sub-cubit:

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

Виджет только отправляет события. Расчёты DSP выполняются сервисами, вызванными
из BLoC/Cubit.

---

## Состояние

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

## Поток данных

```text
Выбор в Visualization/ExperimentViewer
  -> UtilitiesBloc: UtilityWindowChanged
  -> ExperimentSignalReader читает выбранное непрерывное окно
  -> DspService считает спектр/полосы/спектрограмму/предпросмотр фильтра
  -> sub-cubit выдаёт состояние результата
  -> виджет отрисовывает результат
```

`ExperimentSignalReader` читает только выбранные диапазоны отсчётов. Утилиты
никогда не грузят весь `signal.bin`, кроме случая, когда выбранное окно — это весь
файл по явному действию пользователя.

---

## Общие правила

- утилиты не изменяют `signal.bin`;
- расчёты выполняются по непрерывным сегментам;
- разрывы не заполняются;
- результаты диагностические, а не источник истины;
- автоматическая классификация фаз сна не выполняется.

---

## Окно ввода

Вход утилиты:

```text
experiment_id
segment_id
start_segment_sample_index
end_segment_sample_index
sample_rate_hz
samples_microvolts
```

Если окно пересекает разрыв, UI требует выбрать непрерывный участок или анализирует
только валидную часть с явным предупреждением.

---

## Частотный спектр

Параметры:

```text
window_seconds
window_function
frequency_min
frequency_max
```

Результат:

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

## Мощность по полосам

Конфигурация полос настраивается пользователем/лабораторией:

```text
band_id
display_name
frequency_from_hz
frequency_to_hz
color
```

Результат:

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

Мощность по полосам не назначает фазу сна. Автоматическое управление ФБМ по
порогам мощности в MVP не выполняется — ФБМ включает оператор (см.
[`ble.md`](ble.md)).

---

## Спектрограмма

Параметры:

```text
window_seconds
step_seconds
frequency_min
frequency_max
color_scale
```

Спектрограмма показывает разрывы как отсутствующие данные, а не как
интерполированное изображение.

---

## Предпросмотр фильтра

Поддерживаемые типы предпросмотра первого этапа:

```text
notch
band_pass
high_pass
low_pass
```

Фильтры реализуются как IIR Butterworth: high-pass и low-pass — низких порядков,
notch — band-stop. Частоты среза и порядок — параметры предпросмотра, задаются
пользователем. Фильтр применяется к копии выбранного окна.

Предпросмотр фильтра возвращает только отображаемые отсчёты. Отфильтрованный
результат не записывается обратно в источник эксперимента. `signal.bin` всегда
хранит исходные (нефильтрованные) мкВ.

---

## Диагностические логи

`DiagnosticLogCubit` читает `app.log` и показывает:

- время;
- уровень важности;
- подсистема;
- сообщение;
- опциональный код ошибки.

Логи нужны для диагностики и могут включаться в пакет эксперимента как `app.log`.

---

## Проверки реализации

- утилита не может писать в `signal.bin`;
- окно анализа не может молча пересечь разрыв;
- изменение параметров фильтра влияет только на предпросмотр;
- конфигурация полос редактируется без изменений кода;
- просмотрщик логов не разбирает `journal.ndjson` как технический лог.
