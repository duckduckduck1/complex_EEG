import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/core/time_format.dart';
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
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  late String _typeId = _stateTypes.first.id;
  String? _manualError;

  static final List<LabelType> _stateTypes = defaultLabelTypes
      .where((type) => type.kind == AnnotationKind.state)
      .toList(growable: false);

  @override
  void dispose() {
    _noteController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _addManualLabel(RecordingBloc bloc, RecordingState state) {
    final startSeconds = parseClockToSeconds(_startController.text);
    final endSeconds = parseClockToSeconds(_endController.text);
    if (startSeconds == null || endSeconds == null) {
      setState(() => _manualError = 'Время в формате чч:мм:сс или мм:сс');
      return;
    }
    if (endSeconds <= startSeconds) {
      setState(() => _manualError = 'Конец должен быть позже начала');
      return;
    }
    final startSample = secondsToSamples(startSeconds);
    final endSample = secondsToSamples(endSeconds);
    if (endSample > state.sampleCount) {
      setState(() => _manualError = 'Конец позже текущей записи');
      return;
    }
    if (!_intervalFitsSegment(state, startSample, endSample)) {
      setState(
        () => _manualError = 'Интервал попадает на разрыв связи — не выйдет',
      );
      return;
    }
    setState(() => _manualError = null);
    bloc.add(
      RecordingManualIntervalAdded(
        labelTypeId: _typeId,
        startGlobalSampleIndex: startSample,
        endGlobalSampleIndex: endSample,
        note: _blankToNull(_noteController.text),
      ),
    );
    _startController.clear();
    _endController.clear();
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
              final bloc = context.read<RecordingBloc>();
              final canAnnotate = state.status == RecordingStatus.recording;
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
                  _SectionTitle(text: 'Добавить метку вручную'),
                  const SizedBox(height: 4),
                  Text(
                    'Если выбрали не то и удалили — можно поставить метку руками. '
                    'Выберите состояние, введите время начала и конца по часам '
                    'графика (чч:мм:сс или мм:сс). Пример: сон с 00:05:00 до '
                    '00:12:30. Сегмент подтянется сам.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ManualLabelControls(
                    enabled: canAnnotate,
                    types: _stateTypes,
                    selectedTypeId: _typeId,
                    startController: _startController,
                    endController: _endController,
                    errorText: _manualError,
                    onTypeChanged: (id) => setState(() => _typeId = id),
                    onAdd: () => _addManualLabel(bloc, state),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(text: 'Список'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: state.labels.isEmpty ? 96 : 200,
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

bool _intervalFitsSegment(RecordingState state, int start, int end) {
  for (final segment in state.segments) {
    final segmentEnd = segment.endSample ?? state.sampleCount;
    if (segment.startSample <= start && end <= segmentEnd) {
      return true;
    }
  }
  return false;
}

class _ManualLabelControls extends StatelessWidget {
  const _ManualLabelControls({
    required this.enabled,
    required this.types,
    required this.selectedTypeId,
    required this.startController,
    required this.endController,
    required this.errorText,
    required this.onTypeChanged,
    required this.onAdd,
  });

  final bool enabled;
  final List<LabelType> types;
  final String selectedTypeId;
  final TextEditingController startController;
  final TextEditingController endController;
  final String? errorText;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                key: const Key('recording-annotation-manual-type'),
                initialValue: selectedTypeId,
                // Иначе кнопка растягивается под самый широкий пункт словаря
                // и вылезает за отведённую ширину.
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Состояние'),
                items: [
                  for (final type in types)
                    DropdownMenuItem(
                      value: type.id,
                      child: Text(
                        type.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged:
                    enabled
                        ? (value) {
                          if (value != null) onTypeChanged(value);
                        }
                        : null,
              ),
            ),
            SizedBox(
              width: 130,
              child: TextField(
                key: const Key('recording-annotation-manual-start-field'),
                controller: startController,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Начало',
                  hintText: 'чч:мм:сс',
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: TextField(
                key: const Key('recording-annotation-manual-end-field'),
                controller: endController,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Конец',
                  hintText: 'чч:мм:сс',
                ),
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('recording-annotation-add-manual'),
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить'),
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
          title: Text(
            '${_displayName(label.labelTypeId)} · ${label.segmentId}',
          ),
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

String _displayName(String labelTypeId) {
  for (final type in defaultLabelTypes) {
    if (type.id == labelTypeId) {
      return type.displayName;
    }
  }
  return labelTypeId;
}

String _rangeText(AnnotationLabel label) {
  if (label.isPoint) {
    return formatClockFromSamples(label.startSegmentSampleIndex);
  }
  final end = label.endSegmentSampleIndex;
  if (label.isDraft || end == null) {
    return '${formatClockFromSamples(label.startSegmentSampleIndex)} · открыта';
  }
  final durationSeconds = samplesToSeconds(end - label.startSegmentSampleIndex);
  return '${formatClockFromSamples(label.startSegmentSampleIndex)}–'
      '${formatClockFromSamples(end)} · ${formatClock(durationSeconds)}';
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
