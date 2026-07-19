import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/throttled_bloc_builder.dart';

/// Ритмы во вкладке. Темп перерисовки общий с остальными живыми графиками.
class BandPowerWidget extends StatelessWidget {
  final RtEegDataBloc dataBloc;

  const BandPowerWidget({super.key, required this.dataBloc});

  @override
  Widget build(BuildContext context) {
    return ThrottledBlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: dataBloc,
      interval: livePlotRefreshInterval,
      builder: (context, state) {
        if (state is DataUpdated) {
          return BandPowerPlot(
            deltaData: state.deltaPower,
            thetaData: state.thetaPower,
            alphaData: state.alphaPower,
            betaData: state.betaPower,
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
