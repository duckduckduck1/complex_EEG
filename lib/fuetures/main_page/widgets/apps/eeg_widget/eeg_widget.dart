import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/eeg_settings_cubit.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_layout/thrid_hight_layout.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/filter_settings.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/plots.dart';

/// Живые графики одного устройства во вкладке.
///
/// Состав и фильтры приходят из [EegSettingsCubit] — виджет их не хранит.
/// Раньше он держал ссылку на общий изменяемый объект настроек, менял его на
/// месте и звал `setState`, а вкладка сверх того пересоздавала весь виджет по
/// ключу через счётчик ревизии, чтобы панель фильтров перечитала значения.
/// Со значением, которое сравнивается по содержимому, достаточно `BlocBuilder`.
class EegWidget extends StatelessWidget {
  const EegWidget({
    super.key,
    required this.rtEegDataBloc,
    required this.settings,
  });

  final RtEegDataBloc rtEegDataBloc;
  final EegSettingsCubit settings;

  /// Графики показывают фильтрованный сигнал: сырой нужен разве что для отладки.
  static const bool _isFiltered = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EegSettingsCubit, EegSettings>(
      bloc: settings,
      builder: (context, state) {
        final showing = state.eegIsShowingSettings;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              EegWidgetSettingsBar(
                initialSettings: showing,
                onChaged: settings.setShowing,
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildContent(showing, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(EegIsShowingSettings showing, EegSettings state) {
    final signalPlot = EegPlot(dataBloc: rtEegDataBloc, isFiltter: _isFiltered);
    final filterPanel = FillterSettingsWidget(
      initSetting: state.fillterSettings,
      onChanged: settings.setFilters,
    );

    if (showing.isFftShowing && showing.isBandsShowing) {
      return EegLayout(
        isFiltterShowing: showing.isFilterShowing,
        firtsWidget: signalPlot,
        secondWidget: FftPlot(dataBloc: rtEegDataBloc, isFilt: _isFiltered),
        thirdWidget: BandPowerWidget(dataBloc: rtEegDataBloc),
        secondTitle: 'Спектр',
        secondMeta: 'дБ',
        thirdTitle: 'Ритмы',
        thirdMeta: 'отн.',
        fillterWidget: filterPanel,
      );
    }

    if (showing.isFftShowing || showing.isBandsShowing) {
      final onlyBands = showing.isBandsShowing;
      return EegLayout(
        isFiltterShowing: showing.isFilterShowing,
        firtsWidget: signalPlot,
        secondWidget:
            onlyBands
                ? BandPowerWidget(dataBloc: rtEegDataBloc)
                : FftPlot(dataBloc: rtEegDataBloc, isFilt: _isFiltered),
        secondTitle: onlyBands ? 'Ритмы' : 'Спектр',
        secondMeta: onlyBands ? 'отн.' : 'дБ',
        fillterWidget: filterPanel,
      );
    }

    return EegLayout(
      isFiltterShowing: showing.isFilterShowing,
      firtsWidget: signalPlot,
      fillterWidget: filterPanel,
    );
  }
}
