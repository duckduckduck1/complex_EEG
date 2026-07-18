import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/device_view_session.dart';

/// Управление записью прямо в панели мозаики.
///
/// Ради этого мозаика и нужна: оператор с десятью мышами не должен нырять во
/// вкладку, чтобы поставить метку «проснулась». Кнопок ровно три — запись,
/// метка, свет; всё остальное живёт во вкладке, где есть место объяснить.
///
/// Остановка записи спрашивает подтверждение, а старт — нет. Промах по «стоп»
/// обрывает многочасовой эксперимент, промах по «старту» создаёт лишнюю папку,
/// и это несопоставимые цены ошибки.
class MosaicPanelControls extends StatelessWidget {
  const MosaicPanelControls({
    super.key,
    required this.session,
    required this.onStartRecording,
  });

  final DeviceViewSession session;
  final VoidCallback onStartRecording;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecordingBloc, RecordingState>(
      bloc: session.recordingBloc,
      builder: (context, state) {
        final isRecording = state.status == RecordingStatus.recording;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (state.activeDraftLabel != null)
              Expanded(
                child: _ActiveStateChip(
                  labelTypeId: state.activeDraftLabel!.labelTypeId,
                ),
              )
            else
              const Spacer(),
            _PanelIconButton(
              icon: isRecording ? Icons.stop_rounded : Icons.play_arrow_rounded,
              tooltip: isRecording ? 'Завершить запись' : 'Начать эксперимент',
              isDanger: isRecording,
              onPressed:
                  isRecording
                      ? () => _confirmStop(context)
                      : (state.status == RecordingStatus.idle ||
                          state.status == RecordingStatus.stopped ||
                          state.status == RecordingStatus.failed)
                      ? onStartRecording
                      : null,
            ),
            _LabelMenuButton(session: session, state: state),
            _PanelIconButton(
              icon: state.fbmOn ? Icons.lightbulb : Icons.lightbulb_outline,
              tooltip: state.fbmOn ? 'Погасить свет' : 'Включить свет',
              isHighlighted: state.fbmOn,
              onPressed:
                  isRecording
                      ? () => session.recordingBloc.add(
                        state.fbmOn
                            ? const FbmOffRequested()
                            : const FbmOnRequested(),
                      )
                      : null,
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Завершить эксперимент?'),
            content: Text(
              'Запись «${session.title}» остановится и будет закрыта. '
              'Продолжить её потом уже нельзя.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Завершить'),
              ),
            ],
          ),
    );
    if (confirmed ?? false) {
      session.recordingBloc.add(const RecordingStopRequested());
    }
  }
}

/// Какое состояние сейчас размечается. Без этого оператор не видит, что
/// интервал открыт, и метка «спит» тянулась бы до конца записи незамеченной.
class _ActiveStateChip extends StatelessWidget {
  const _ActiveStateChip({required this.labelTypeId});

  final String labelTypeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = defaultLabelTypes.firstWhere(
      (labelType) => labelType.id == labelTypeId,
      orElse:
          () => const LabelType(
            id: '',
            kind: AnnotationKind.state,
            displayName: 'метка',
            colorHex: '#FFFFFF',
          ),
    );
    return Row(
      children: [
        Icon(
          Icons.radio_button_checked,
          size: 12,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            type.displayName,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Метки одним меню: открыть состояние, закрыть открытое, отметить событие.
class _LabelMenuButton extends StatelessWidget {
  const _LabelMenuButton({required this.session, required this.state});

  final DeviceViewSession session;
  final RecordingState state;

  @override
  Widget build(BuildContext context) {
    final isRecording = state.status == RecordingStatus.recording;
    final activeDraft = state.activeDraftLabel;
    final states = defaultLabelTypes
        .where((type) => type.kind == AnnotationKind.state && type.isActive)
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final events = defaultLabelTypes
        .where((type) => type.kind == AnnotationKind.event && type.isActive)
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return MenuAnchor(
      menuChildren: [
        if (activeDraft != null)
          MenuItemButton(
            onPressed:
                () => session.recordingBloc.add(
                  const RecordingActiveStateLabelClosed(),
                ),
            leadingIcon: const Icon(Icons.stop_circle_outlined, size: 16),
            child: const SizedBox(width: 180, child: Text('Закрыть состояние')),
          ),
        for (final type in states)
          MenuItemButton(
            onPressed:
                () => session.recordingBloc.add(
                  RecordingStateLabelStarted(labelTypeId: type.id),
                ),
            leadingIcon: const Icon(Icons.timeline, size: 16),
            child: SizedBox(width: 180, child: Text(type.displayName)),
          ),
        for (final type in events)
          MenuItemButton(
            onPressed:
                () => session.recordingBloc.add(
                  RecordingPointLabelAdded(labelTypeId: type.id),
                ),
            leadingIcon: const Icon(Icons.push_pin_outlined, size: 16),
            child: SizedBox(width: 180, child: Text(type.displayName)),
          ),
      ],
      builder:
          (context, controller, _) => _PanelIconButton(
            icon: Icons.bookmark_add_outlined,
            tooltip: 'Поставить метку',
            onPressed:
                isRecording
                    ? () =>
                        controller.isOpen
                            ? controller.close()
                            : controller.open()
                    : null,
          ),
    );
  }
}

/// Кнопка размером под панель: штатная IconButton съедает 48 px высоты,
/// которых на панели нет.
class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDanger = false,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDanger;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        onPressed == null
            ? colorScheme.outline.withValues(alpha: 0.5)
            : isDanger
            ? colorScheme.error
            : isHighlighted
            ? colorScheme.tertiary
            : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
