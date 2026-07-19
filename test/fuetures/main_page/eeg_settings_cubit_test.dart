import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/eeg_settings_cubit.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/eeg_settings.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/fillter_settings_class.dart';

void main() {
  late EegSettingsCubit cubit;

  setUp(() => cubit = EegSettingsCubit());
  tearDown(() async => cubit.close());

  test('смена фильтров не задевает состав графиков', () {
    cubit.setShowing(const EegIsShowingSettings(isBandsShowing: true));
    cubit.setFilters(const FillterSettings(isLpOn: true, lp: 30));

    expect(cubit.state.eegIsShowingSettings.isBandsShowing, isTrue);
    expect(cubit.state.fillterSettings.lp, 30);
  });

  test('одинаковые настройки не порождают новое состояние', () async {
    // Ради этого настройки и стали значением: раньше объект менялся на месте,
    // отличить «изменилось» от «то же самое» было нельзя, и вкладка дёргала
    // счётчик ревизии, пересоздавая весь виджет графиков.
    final states = <EegSettings>[];
    final sub = cubit.stream.listen(states.add);

    const filters = FillterSettings(isLpOn: true, lp: 30);
    cubit.setFilters(filters);
    cubit.setFilters(filters);
    cubit.setFilters(const FillterSettings(isLpOn: true, lp: 30));
    await pumpEventQueue();
    await sub.cancel();

    expect(states, hasLength(1));
  });

  test('фильтры записи переносятся на график целиком', () {
    cubit.applyRecordingFilters(
      const RecordingFilters(
        lpHz: 35,
        hpHz: 1.5,
        notchHz: 50,
        isLpEnabled: true,
        isHpEnabled: true,
        isNotchEnabled: false,
      ),
    );

    final filters = cubit.state.fillterSettings;
    expect(filters.lp, 35);
    expect(filters.hp, 1.5);
    expect(filters.isLpOn, isTrue);
    expect(filters.isHpOn, isTrue);
    expect(
      filters.isNotchOn,
      isFalse,
      reason: 'выключенный при записи фильтр не должен включаться на графике',
    );
  });
}
