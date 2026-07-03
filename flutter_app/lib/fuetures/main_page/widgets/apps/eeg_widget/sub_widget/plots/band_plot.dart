import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';

class BandPowerWidget extends StatelessWidget {
  final RtEegDataBloc dataBloc;

  const BandPowerWidget({super.key, required this.dataBloc});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: dataBloc,
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
