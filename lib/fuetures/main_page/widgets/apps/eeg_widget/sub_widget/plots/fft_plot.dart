import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';

class FftPlot extends StatefulWidget {
  final RtEegDataBloc dataBloc;
  final bool isFilt;
  const FftPlot({super.key, required this.dataBloc, required this.isFilt});

  @override
  State<FftPlot> createState() => _FftPlotState();
}

class _FftPlotState extends State<FftPlot> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: widget.dataBloc,
      builder: (context, state) {
        if (state is DataUpdated) {
          return FrequencyPlot(
            data: widget.isFilt ? state.filtSpectrum : state.spectrum,
            paddingFactor: 0.35,
            showTooltip: true,
            maxFrequency: 70,
          );
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}
