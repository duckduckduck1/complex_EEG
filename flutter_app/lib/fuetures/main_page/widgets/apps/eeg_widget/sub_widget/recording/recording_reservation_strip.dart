import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/features/recording/application/recording_bloc.dart';
import 'package:iot/features/recording/domain/recording_models.dart';

class RecordingReservationStrip extends StatelessWidget {
  const RecordingReservationStrip({
    super.key,
    required this.recordingBloc,
    required this.onStartPressed,
  });

  final RecordingBloc? recordingBloc;
  final VoidCallback? onStartPressed;

  @override
  Widget build(BuildContext context) {
    final bloc = recordingBloc;
    if (bloc == null) {
      return _StripShell(
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

  const _RecordingControls({required this.state, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final segmentLabel = state.activeSegmentId ?? 'seg_1';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        _StatusToken(
          icon: Icons.fiber_manual_record,
          label: 'Запись',
          color: colorScheme.error,
        ),
        _StatusToken(
          icon: Icons.timer_outlined,
          label: _formatDuration(state.sampleCount),
          color: colorScheme.onSurfaceVariant,
        ),
        _StatusToken(
          icon: Icons.timeline,
          label: segmentLabel,
          color: colorScheme.primary,
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

String _formatDuration(int sampleCount) {
  final seconds = sampleCount ~/ 250;
  final minutes = seconds ~/ 60;
  final restSeconds = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${restSeconds.toString().padLeft(2, '0')}';
}
