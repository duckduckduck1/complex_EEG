import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/throttled_bloc_builder.dart';

/// Спектр во вкладке. Темп перерисовки общий с остальными живыми графиками.
class FftPlot extends StatelessWidget {
  final RtEegDataBloc dataBloc;
  final bool isFilt;

  const FftPlot({super.key, required this.dataBloc, required this.isFilt});

  @override
  Widget build(BuildContext context) {
    return ThrottledBlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: dataBloc,
      interval: livePlotRefreshInterval,
      builder: (context, state) {
        if (state is DataUpdated) {
          return FrequencyPlot(
            data: isFilt ? dataBloc.filteredSpectrum : dataBloc.spectrum,
            paddingFactor: 0.35,
            showTooltip: true,
            maxFrequency: 70,
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
