import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/throttled_bloc_builder.dart';

/// Живой сигнал во вкладке.
///
/// Перерисовка ограничена кадровым темпом, как и в мозаике: раньше вкладка
/// строилась на каждый отсчёт, то есть 250 раз в секунду при 60 кадрах экрана —
/// четыре перестройки из пяти уходили в мусор и отнимали время у самой
/// отрисовки. Отсюда и ощущение, что мозаика идёт глаже вкладки.
class EegPlot extends StatelessWidget {
  final RtEegDataBloc dataBloc;
  final bool isFiltter;

  const EegPlot({super.key, required this.dataBloc, required this.isFiltter});

  @override
  Widget build(BuildContext context) {
    return ThrottledBlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: dataBloc,
      interval: livePlotRefreshInterval,
      builder: (context, state) {
        if (state is DataUpdated) {
          return PlotScafold(
            // Точки берём из bloc в момент отрисовки: состояние их не носит.
            data: isFiltter ? dataBloc.filteredSpots : dataBloc.rawSpots,
            paddingFactor: 0.35,
          );
        }
        return Container();
      },
    );
  }
}
