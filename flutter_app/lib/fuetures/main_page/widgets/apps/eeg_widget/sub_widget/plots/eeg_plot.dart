import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plot_scafold/plot_scafolds.dart';

class EegPlot extends StatefulWidget {
  final RtEegDataBloc dataBloc;
  final bool isFiltter;
  const EegPlot({super.key, required this.dataBloc, required this.isFiltter});

  @override
  State<EegPlot> createState() => _EegPlotState();
}

class _EegPlotState extends State<EegPlot> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RtEegDataBloc, RtEegState>(
      bloc: widget.dataBloc,
      builder: (context, state) {
        if (state is DataUpdated) {
          return PlotScafold(
            data: widget.isFiltter ? state.filterData : state.newData,
            paddingFactor: 0.35,
          );
        }
        return Container();
      },
    );
  }
}
