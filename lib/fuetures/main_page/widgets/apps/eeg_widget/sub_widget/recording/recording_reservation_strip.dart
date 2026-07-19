import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';

class RecordingReservationStrip extends StatelessWidget {
  const RecordingReservationStrip({
    super.key,
    required this.recordingBloc,
    required this.onStartPressed,
    this.onAnnotationsPressed,
    this.onReconnectPressed,
  });

  final RecordingBloc? recordingBloc;
  final VoidCallback? onStartPressed;
  final VoidCallback? onAnnotationsPressed;
  final VoidCallback? onReconnectPressed;

  @override
  Widget build(BuildContext context) {
    final bloc = recordingBloc;
    if (bloc == null) {
      return const _StripShell(
        child: _MutedStatus(
          icon: Icons.tab_outlined,
          text: 'Откройте вкладку устройства для записи',
        ),
      );
    }

    return BlocBuilder<RecordingBloc, RecordingState>(
      bloc: bloc,
      builder: (context, state) {
        return _StripShell(
          child: switch (state.status) {
            RecordingStatus.recording => _RecordingControls(
              state: state,
              onStop: () => bloc.add(const RecordingStopRequested()),
              onToggleFbm:
                  () => bloc.add(
                    state.fbmOn
                        ? const FbmOffRequested()
                        : const FbmOnRequested(),
                  ),
              onPwmChanged: (value) => bloc.add(FbmPwmChanged(value)),
              onAutoOffChanged:
                  (seconds) => bloc.add(FbmAutoOffChanged(seconds)),
              onStartState:
                  (id) => bloc.add(RecordingStateLabelStarted(labelTypeId: id)),
              onCloseState:
                  () => bloc.add(const RecordingActiveStateLabelClosed()),
              onAddEvent:
                  (id) => bloc.add(RecordingPointLabelAdded(labelTypeId: id)),
              onAnnotationsPressed: onAnnotationsPressed,
            ),
            RecordingStatus.pausedByDisconnect => _PausedControls(
              onReconnectPressed: onReconnectPressed,
              onStop: () => bloc.add(const RecordingStopRequested()),
            ),
            RecordingStatus.preparing ||
            RecordingStatus.stopping => const _BusyControls(),
            RecordingStatus.failed => _StartControls(
              label: 'Повторить старт',
              errorText: state.lastError?.message,
              onStartPressed: onStartPressed,
            ),
            _ => _StartControls(
              label: 'Начать эксперимент',
              onStartPressed: onStartPressed,
            ),
          },
        );
      },
    );
  }
}

class _StripShell extends StatelessWidget {
  final Widget child;

  const _StripShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('eeg-recording-reservation-strip'),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.92)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: child,
      ),
    );
  }
}

class _PausedControls extends StatelessWidget {
  final VoidCallback? onReconnectPressed;
  final VoidCallback onStop;

  const _PausedControls({
    required this.onReconnectPressed,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _MutedStatus(
      icon: Icons.link_off_rounded,
      text: 'Связь потеряна, запись на паузе',
      color: colorScheme.error,
    );
    final reconnectButton = FilledButton.icon(
      onPressed: onReconnectPressed,
      icon: const Icon(Icons.bluetooth_searching_rounded),
      label: const Text('Переподключиться'),
    );
    final stopButton = OutlinedButton.icon(
      onPressed: onStop,
      icon: const Icon(Icons.stop_rounded),
      label: const Text('Завершить'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [reconnectButton, stopButton],
        );
        if (constraints.maxWidth < 520) {
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: constraints.maxWidth, child: status),
              buttons,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: status),
            const SizedBox(width: 12),
            buttons,
          ],
        );
      },
    );
  }
}

class _StartControls extends StatelessWidget {
  final String label;
  final String? errorText;
  final VoidCallback? onStartPressed;

  const _StartControls({
    required this.label,
    this.errorText,
    required this.onStartPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = _MutedStatus(
      icon: Icons.fiber_manual_record,
      text: errorText ?? 'Запись эксперимента не идёт',
      color: errorText == null ? null : colorScheme.error,
    );
    final button = FilledButton.icon(
      onPressed: onStartPressed,
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(label),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: constraints.maxWidth, child: status),
              button,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: status),
            const SizedBox(width: 12),
            button,
          ],
        );
      },
    );
  }
}

class _BusyControls extends StatelessWidget {
  const _BusyControls();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Text('Подготовка записи…')),
      ],
    );
  }
}

class _RecordingControls extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onStop;
  final VoidCallback onToggleFbm;
  final ValueChanged<int> onPwmChanged;
  final ValueChanged<int?> onAutoOffChanged;
  final ValueChanged<String> onStartState;
  final VoidCallback onCloseState;
  final ValueChanged<String> onAddEvent;
  final VoidCallback? onAnnotationsPressed;

  const _RecordingControls({
    required this.state,
    required this.onStop,
    required this.onToggleFbm,
    required this.onPwmChanged,
    required this.onAutoOffChanged,
    required this.onStartState,
    required this.onCloseState,
    required this.onAddEvent,
    required this.onAnnotationsPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final segmentLabel = state.activeSegmentId ?? 'seg_1';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        _StatusToken(
          icon: Icons.fiber_manual_record,
          label: 'Запись',
          color: colorScheme.error,
        ),
        _StatusToken(
          icon: Icons.timer_outlined,
          label: formatClockFromSamples(state.sampleCount),
          color: colorScheme.onSurfaceVariant,
        ),
        _StatusToken(
          icon: Icons.timeline,
          label: segmentLabel,
          color: colorScheme.primary,
        ),
        FilledButton.tonalIcon(
          onPressed: onToggleFbm,
          icon: Icon(state.fbmOn ? Icons.lightbulb : Icons.lightbulb_outline),
          // Пока свет горит — на кнопке идёт время сеанса, чтобы оператор видел
          // длительность, не заглядывая в json.
          label: Text(
            state.fbmOn
                ? 'Свет выкл · ${formatClockFromSamples(state.fbmElapsedSamples ?? 0)}'
                : 'Свет вкл',
          ),
        ),
        _PwmControl(
          value: state.pwmLevel ?? 50,
          enabled: state.status == RecordingStatus.recording,
          onChanged: onPwmChanged,
        ),
        _FbmAutoOffControl(
          seconds: state.fbmAutoOffSeconds,
          onChanged: onAutoOffChanged,
        ),
        _StatePicker(
          activeDraft: state.activeDraftLabel,
          elapsedSampleCount: state.sampleCount,
          onStartState: onStartState,
          onCloseState: onCloseState,
        ),
        _EventPicker(onAddEvent: onAddEvent),
        OutlinedButton.icon(
          onPressed: onAnnotationsPressed,
          icon: const Icon(Icons.list_alt_outlined),
          label: const Text('Список'),
        ),
        OutlinedButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Остановить'),
        ),
      ],
    );
  }
}

/// Выкатывающийся список состояний. Пока метка не открыта — кнопка «Метка»
/// разворачивает прокручиваемый список; выбор запускает состояние. Пока метка
/// идёт — кнопка окрашивается в цвет метки и превращается в «стоп» с таймером
/// в секундах от начала состояния. Переключение состояний закрывает предыдущее
/// автоматически (это делает RecordingBloc), поэтому оператору не нужно думать
/// про «закрыть».
class _StatePicker extends StatelessWidget {
  final AnnotationLabel? activeDraft;
  final int elapsedSampleCount;
  final ValueChanged<String> onStartState;
  final VoidCallback onCloseState;

  const _StatePicker({
    required this.activeDraft,
    required this.elapsedSampleCount,
    required this.onStartState,
    required this.onCloseState,
  });

  @override
  Widget build(BuildContext context) {
    final draft = activeDraft;
    if (draft != null) {
      final type = _labelType(draft.labelTypeId);
      final color = _colorOf(type, Theme.of(context).colorScheme.primary);
      final elapsed = formatClockFromSamples(
        elapsedSampleCount - draft.globalStartSampleIndex,
      );
      return FilledButton.icon(
        onPressed: onCloseState,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: const Color(0xFF0D1117),
        ),
        icon: const Icon(Icons.stop_rounded),
        label: Text('${type?.displayName ?? draft.labelTypeId} · $elapsed'),
      );
    }

    return MenuAnchor(
      menuChildren: _labelMenuItems(context, _statesInOrder, onStartState),
      builder:
          (context, controller, _) => OutlinedButton.icon(
            onPressed:
                () =>
                    controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.sell_outlined),
            label: const Text('Метка'),
          ),
    );
  }
}

/// Быстрые точечные события: один клик — метка на текущем отсчёте.
class _EventPicker extends StatelessWidget {
  final ValueChanged<String> onAddEvent;

  const _EventPicker({required this.onAddEvent});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: _labelMenuItems(context, _eventsInOrder, onAddEvent),
      builder:
          (context, controller, _) => OutlinedButton.icon(
            onPressed:
                () =>
                    controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.bolt_outlined),
            label: const Text('Событие'),
          ),
    );
  }
}

/// Пункты выкатывающегося списка: цветная точка + название. Меню само крутится
/// колесиком, если длинное. Общее для состояний и событий.
List<Widget> _labelMenuItems(
  BuildContext context,
  List<LabelType> types,
  ValueChanged<String> onSelected,
) {
  final fallback = Theme.of(context).colorScheme.primary;
  return [
    for (final type in types)
      MenuItemButton(
        onPressed: () => onSelected(type.id),
        leadingIcon: Icon(
          Icons.circle,
          size: 12,
          color: _colorOf(type, fallback),
        ),
        child: SizedBox(width: 176, child: Text(type.displayName)),
      ),
  ];
}

/// Автовыключение ФБМ: свет гаснет сам через выбранное время.
///
/// Ручное включение и выключение остаётся — таймер только добавляет «не забыть
/// погасить». «Вручную» означает, что сам не гаснет.
class _FbmAutoOffControl extends StatelessWidget {
  final int? seconds;
  final ValueChanged<int?> onChanged;

  const _FbmAutoOffControl({required this.seconds, required this.onChanged});

  static const _presets = <int?, String>{
    null: 'Вручную',
    30: '30 с',
    60: '1 мин',
    300: '5 мин',
    900: '15 мин',
    1800: '30 мин',
  };

  /// Подпись кнопки: у пресета своя, у произвольного времени — само время.
  String get _label {
    final current = seconds;
    if (current == null) return 'Вручную';
    return _presets[current] ?? formatClock(current);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final preset in _presets.entries)
          MenuItemButton(
            onPressed: () => onChanged(preset.key),
            leadingIcon: Icon(
              preset.key == seconds ? Icons.check : Icons.timer_outlined,
              size: 16,
            ),
            child: SizedBox(width: 140, child: Text(preset.value)),
          ),
        MenuItemButton(
          onPressed: () => _askCustomTime(context),
          leadingIcon: Icon(
            seconds != null && !_presets.containsKey(seconds)
                ? Icons.check
                : Icons.edit_outlined,
            size: 16,
          ),
          child: const SizedBox(width: 140, child: Text('Своё время…')),
        ),
      ],
      builder:
          (context, controller, _) => OutlinedButton.icon(
            onPressed:
                () =>
                    controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.timer_outlined),
            label: Text('Гасить: $_label'),
          ),
    );
  }

  Future<void> _askCustomTime(BuildContext context) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _FbmAutoOffDialog(initialSeconds: seconds),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }
}

/// Ввод произвольного времени автовыключения в `чч:мм:сс`.
class _FbmAutoOffDialog extends StatefulWidget {
  final int? initialSeconds;

  const _FbmAutoOffDialog({required this.initialSeconds});

  @override
  State<_FbmAutoOffDialog> createState() => _FbmAutoOffDialogState();
}

class _FbmAutoOffDialogState extends State<_FbmAutoOffDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: formatClock(widget.initialSeconds ?? 0),
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseClockToSeconds(_controller.text);
    if (parsed == null || parsed <= 0) {
      setState(() => _errorText = 'Введите время в формате чч:мм:сс');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Через сколько гасить свет'),
      content: TextField(
        key: const Key('fbm-auto-off-input'),
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'чч:мм:сс',
          helperText: 'Можно короче: «90» — это 90 секунд, «5:00» — 5 минут',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Готово')),
      ],
    );
  }
}

class _PwmControl extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _PwmControl({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ШИМ $value',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 1,
              max: 99,
              divisions: 98,
              label: '$value',
              onChanged: enabled ? (value) => onChanged(value.round()) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedStatus extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _MutedStatus({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveColor = color ?? colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: effectiveColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusToken extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusToken({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(label, style: textStyle),
      ],
    );
  }
}

final List<LabelType> _statesInOrder = defaultLabelTypes
  .where((type) => type.kind == AnnotationKind.state && type.isActive)
  .toList(growable: false)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

final List<LabelType> _eventsInOrder = defaultLabelTypes
  .where((type) => type.kind == AnnotationKind.event && type.isActive)
  .toList(growable: false)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

LabelType? _labelType(String id) {
  for (final type in defaultLabelTypes) {
    if (type.id == id) {
      return type;
    }
  }
  return null;
}

Color _colorOf(LabelType? type, Color fallback) {
  if (type == null) {
    return fallback;
  }
  final hex = type.colorHex.replaceFirst('#', '');
  final value = int.tryParse(hex, radix: 16);
  if (value == null || hex.length != 6) {
    return fallback;
  }
  return Color(0xFF000000 | value);
}
