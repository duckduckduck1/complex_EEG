import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_decimation.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';

/// Графики для панели мозаики.
///
/// Это те же графики, что во вкладке, только в компактном режиме: оси со
/// значениями и подсказка по ритмам остаются, уходят легенда, зум и половина
/// засечек. Отдельной реализации нет намеренно — она разошлась бы с вкладкой
/// по формату времени, шагу засечек и стабилизации масштаба.

/// Сигнал одного устройства.
class MosaicSignalPlot extends StatelessWidget {
  const MosaicSignalPlot({super.key, required this.data});

  final List<FlSpot> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _WaitingForSignal();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Прореживаем под ту ширину, в которую реально рисуем: больше точек,
        // чем пикселей, всё равно не увидеть, а стоят они полной цены.
        final spots = decimateMinMax(data, constraints.maxWidth.round());
        return RepaintBoundary(
          child: PlotScafold(data: spots, paddingFactor: 0.35, compact: true),
        );
      },
    );
  }
}

/// Ритмы одного устройства.
///
/// Точка добавляется раз в секунду и хранится их 60, поэтому прореживать тут
/// нечего — график дешёвый и помещается целиком.
class MosaicBandsPlot extends StatelessWidget {
  const MosaicBandsPlot({
    super.key,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
  });

  final List<FlSpot> delta;
  final List<FlSpot> theta;
  final List<FlSpot> alpha;
  final List<FlSpot> beta;

  @override
  Widget build(BuildContext context) {
    if (delta.isEmpty && theta.isEmpty && alpha.isEmpty && beta.isEmpty) {
      return const _WaitingForSignal();
    }
    return RepaintBoundary(
      child: BandPowerPlot(
        deltaData: delta,
        thetaData: theta,
        alphaData: alpha,
        betaData: beta,
        compact: true,
      ),
    );
  }
}

class _WaitingForSignal extends StatelessWidget {
  const _WaitingForSignal();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'ждём сигнал',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
      ),
    );
  }
}
