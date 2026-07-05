import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_layout/thrid_hight_layout.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/filter_settings.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plots.dart';

class EegWidget extends StatefulWidget {
  final RtEegDataBloc rtEegDataBloc;
  final double eegToFftRatio;
  final double filterToEegRatio;

  const EegWidget({
    super.key,
    required this.rtEegDataBloc,
    this.eegToFftRatio = 2.0,
    this.filterToEegRatio = 2,
  });

  @override
  State<EegWidget> createState() => _EegWidgetState();
}

class _EegWidgetState extends State<EegWidget> {
  final bool _isFiltter = true;
  late EegSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.rtEegDataBloc.eegSettings;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            EegWidgetSettingsBar(
              initialSettings:
                  widget.rtEegDataBloc.eegSettings.eegIsShowingSettings,
              onChaged: (val) {
                _settings.eegIsShowingSettings = val;
                widget.rtEegDataBloc.add(NewSettings(newSettings: _settings));
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (widget.rtEegDataBloc.eegSettings.eegIsShowingSettings.isFftShowing &&
        widget.rtEegDataBloc.eegSettings.eegIsShowingSettings.isBandsShowing) {
      return EegLayout(
        isFiltterShowing:
            widget
                .rtEegDataBloc
                .eegSettings
                .eegIsShowingSettings
                .isFilterShowing,
        firtsWidget: EegPlot(
          dataBloc: widget.rtEegDataBloc,
          isFiltter: _isFiltter,
        ),
        secondWidget: FftPlot(
          dataBloc: widget.rtEegDataBloc,
          isFilt: _isFiltter,
        ),
        thirdWidget: BandPowerWidget(dataBloc: widget.rtEegDataBloc),
        fillterWidget: _buildFilterSettings(),
      );
    }

    if (widget.rtEegDataBloc.eegSettings.eegIsShowingSettings.isFftShowing ||
        widget.rtEegDataBloc.eegSettings.eegIsShowingSettings.isBandsShowing) {
      return EegLayout(
        isFiltterShowing:
            widget
                .rtEegDataBloc
                .eegSettings
                .eegIsShowingSettings
                .isFilterShowing,
        firtsWidget: EegPlot(
          dataBloc: widget.rtEegDataBloc,
          isFiltter: _isFiltter,
        ),
        secondWidget:
            widget.rtEegDataBloc.eegSettings.eegIsShowingSettings.isBandsShowing
                ? BandPowerWidget(dataBloc: widget.rtEegDataBloc)
                : FftPlot(dataBloc: widget.rtEegDataBloc, isFilt: _isFiltter),
        fillterWidget: _buildFilterSettings(),
      );
    }

    return EegLayout(
      isFiltterShowing:
          widget.rtEegDataBloc.eegSettings.eegIsShowingSettings.isFilterShowing,
      firtsWidget: EegPlot(
        dataBloc: widget.rtEegDataBloc,
        isFiltter: _isFiltter,
      ),
      fillterWidget: _buildFilterSettings(),
    );
  }

  Widget _buildFilterSettings() {
    return FillterSettingsWidget(
      initSetting: widget.rtEegDataBloc.eegSettings.fillterSettings,
      onChanged: (val) {
        _settings.fillterSettings = val;
        widget.rtEegDataBloc.add(NewSettings(newSettings: _settings));
        setState(() {});
      },
    );
  }
}
