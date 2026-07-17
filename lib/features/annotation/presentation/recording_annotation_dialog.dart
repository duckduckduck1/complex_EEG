import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';

Future<void> showRecordingAnnotationDialog({
  required BuildContext context,
  required RecordingBloc recordingBloc,
}) {
  return showDialog<void>(
    context: context,
    builder:
        (context) => BlocProvider<RecordingBloc>.value(
          value: recordingBloc,
          child: const RecordingAnnotationDialog(),
        ),
  );
}

class RecordingAnnotationDialog extends StatefulWidget {
  const RecordingAnnotationDialog({super.key});

  @override
  State<RecordingAnnotationDialog> createState() =>
      _RecordingAnnotationDialogState();
}

class _RecordingAnnotationDialogState extends State<RecordingAnnotationDialog> {
  final _noteController = TextEditingController();
  final _excludeStartController = TextEditingController(text: '0');
  final _excludeEndController = TextEditingController(text: '0');
  String? _excludeError;

  @override
  void dispose() {
    _noteController.dispose();
    _excludeStartController.dispose();
    _excludeEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: BlocBuilder<RecordingBloc, RecordingState>(
            builder: (context, state) {
              final canAnnotate = state.status == RecordingStatus.recording;
              final activeSegment =
                  state.activeSegmentId == null
                      ? null
                      : state.segments
                          .where(
                            (segment) =>
                                segment.segmentId == state.activeSegmentId,
                          )
                          .firstOrNull;
              final currentSegmentSampleCount =
                  activeSegment == null
                      ? null
                      : state.sampleCount - activeSegment.startSample;
              return ListView(
                key: const Key('recording-annotation-scroll'),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sell_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Метки эксперимента',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('recording-annotation-note-field'),
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(text: 'Состояние'),
                  const SizedBox(height: 8),
                  _StateButtons(
                    enabled: canAnnotate,
                    activeLabelTypeId: state.activeDraftLabel?.labelTypeId,
                    noteController: _noteController,
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(text: 'Событие'),
                  const SizedBox(height: 8),
                  _EventButtons(
                    enabled: canAnnotate,
                    noteController: _noteController,
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(text: 'Бракованный интервал'),
                  const SizedBox(height: 8),
                  _ExcludeIntervalControls(
                    enabled: canAnnotate,
                    startController: _excludeStartController,
                    endController: _excludeEndController,
                    noteController: _noteController,
                    maxSegmentSampleIndex: currentSegmentSampleCount,
                    errorText: _excludeError,
                    onValidationError:
                        (message) => setState(() => _excludeError = message),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(text: 'Список'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: state.labels.isEmpty ? 96 : 180,
                    child: _LabelsList(labels: state.labels),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StateButtons extends StatelessWidget {
  const _StateButtons({
    required this.enabled,
    required this.activeLabelTypeId,
    required this.noteController,
  });

  final bool enabled;
  final String? activeLabelTypeId;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RecordingBloc>();
    final stateTypes = defaultLabelTypes
        .where((type) => type.kind == AnnotationKind.state)
        .toList(growable: false);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in stateTypes)
          FilledButton.tonal(
            onPressed:
                enabled && activeLabelTypeId == null
                    ? () => bloc.add(
                      RecordingStateLabelStarted(
                        labelTypeId: type.id,
                        note: _blankToNull(noteController.text),
                      ),
                    )
                    : null,
            child: Text(type.displayName),
          ),
        OutlinedButton.icon(
          onPressed:
              enabled && activeLabelTypeId != null
                  ? () => bloc.add(const RecordingActiveStateLabelClosed())
                  : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Закрыть активную'),
        ),
      ],
    );
  }
}

class _EventButtons extends StatelessWidget {
  const _EventButtons({required this.enabled, required this.noteController});

  final bool enabled;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RecordingBloc>();
    final eventTypes = defaultLabelTypes
        .where((type) => type.kind == AnnotationKind.event)
        .toList(growable: false);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in eventTypes)
          OutlinedButton(
            onPressed:
                enabled
                    ? () => bloc.add(
                      RecordingPointLabelAdded(
                        labelTypeId: type.id,
                        note: _blankToNull(noteController.text),
                      ),
                    )
                    : null,
            child: Text(type.displayName),
          ),
      ],
    );
  }
}

class _ExcludeIntervalControls extends StatelessWidget {
  const _ExcludeIntervalControls({
    required this.enabled,
    required this.startController,
    required this.endController,
    required this.noteController,
    required this.maxSegmentSampleIndex,
    required this.errorText,
    required this.onValidationError,
  });

  final bool enabled;
  final TextEditingController startController;
  final TextEditingController endController;
  final TextEditingController noteController;
  final int? maxSegmentSampleIndex;
  final String? errorText;
  final ValueChanged<String?> onValidationError;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RecordingBloc>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                key: const Key('recording-annotation-exclude-start-field'),
                controller: startController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Старт'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextField(
                key: const Key('recording-annotation-exclude-end-field'),
                controller: endController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Конец'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              key: const Key('recording-annotation-add-exclude'),
              onPressed:
                  enabled
                      ? () {
                        final start = int.tryParse(startController.text.trim());
                        final end = int.tryParse(endController.text.trim());
                        if (start == null || end == null) {
                          onValidationError('Введите числовые границы');
                          return;
                        }
                        if (start < 0 || end <= start) {
                          onValidationError(
                            'Интервал должен быть непустым: start < end',
                          );
                          return;
                        }
                        final maxIndex = maxSegmentSampleIndex;
                        if (maxIndex != null && end > maxIndex) {
                          onValidationError(
                            'Конец интервала выходит за текущий сегмент',
                          );
                          return;
                        }
                        onValidationError(null);
                        bloc.add(
                          RecordingExcludeIntervalAdded(
                            labelTypeId: 'bad_segment',
                            startSegmentSampleIndex: start,
                            endSegmentSampleIndex: end,
                            note: _blankToNull(noteController.text),
                          ),
                        );
                      }
                      : null,
              icon: const Icon(Icons.block_rounded),
              label: const Text('Добавить брак'),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _LabelsList extends StatelessWidget {
  const _LabelsList({required this.labels});

  final List<AnnotationLabel> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return Center(
        child: Text(
          'Метки пока не добавлены',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: labels.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final label = labels[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_iconFor(label.kind)),
          title: Text('${label.labelTypeId} · ${label.kind.name}'),
          subtitle: Text(_rangeText(label)),
          trailing: IconButton(
            tooltip: 'Удалить',
            onPressed:
                () => context.read<RecordingBloc>().add(
                  RecordingAnnotationDeleted(label.id),
                ),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

IconData _iconFor(AnnotationKind kind) {
  return switch (kind) {
    AnnotationKind.state => Icons.bedtime_outlined,
    AnnotationKind.event => Icons.add_location_alt_outlined,
    AnnotationKind.exclude => Icons.block_rounded,
  };
}

String _rangeText(AnnotationLabel label) {
  if (label.isPoint) {
    return 'seg ${label.segmentId}, sample ${label.startSegmentSampleIndex}';
  }
  final end = label.endSegmentSampleIndex;
  final suffix = label.isDraft ? ' · открыта' : '';
  return 'seg ${label.segmentId}, ${label.startSegmentSampleIndex}–${end ?? '?'}$suffix';
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
