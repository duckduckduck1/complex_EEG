import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/exp_widget.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/recording/recording_reservation_strip.dart';
import 'package:iot/theme.dart';

void main() {
  Widget wrap(Widget child, {double width = 360}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: SizedBox(width: width, child: child)),
    );
  }

  testWidgets('EEG visibility controls are compact and update settings', (
    tester,
  ) async {
    var latestSettings = EegIsShowingSettings();

    await tester.pumpWidget(
      wrap(
        EegWidgetSettingsBar(
          initialSettings: latestSettings,
          onChaged: (settings) => latestSettings = settings,
        ),
        width: 220,
      ),
    );

    expect(find.text('Фильтр'), findsOneWidget);
    expect(find.text('Спектр'), findsOneWidget);
    expect(find.text('Ритмы'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Спектр'));
    await tester.pumpAndSettle();

    expect(latestSettings.isFftShowing, isTrue);
  });

  testWidgets('disabled filters keep their displayed frequency values', (
    tester,
  ) async {
    final initialSettings = FillterSettings(
      lp: 42.5,
      hp: 0.5,
      notch: 50,
      isLpOn: false,
      isHpOn: false,
      isNotchOn: false,
    );

    await tester.pumpWidget(
      wrap(
        FillterSettingsWidget(initSetting: initialSettings, onChanged: (_) {}),
      ),
    );

    expect(find.text('LP'), findsOneWidget);
    expect(find.text('HP'), findsOneWidget);
    expect(find.text('Notch'), findsOneWidget);
    expect(find.text('42.5 Hz'), findsOneWidget);
    expect(find.text('0.5 Hz'), findsOneWidget);
    expect(find.text('50.0 Hz'), findsOneWidget);
    expect(find.text('выкл'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
  testWidgets('recording reservation strip fits compact width', (tester) async {
    await tester.pumpWidget(
      wrap(const RecordingReservationStrip(), width: 320),
    );

    expect(
      find.byKey(const Key('eeg-recording-reservation-strip')),
      findsOneWidget,
    );
    expect(find.text('Запись'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Метки'), findsOneWidget);
    expect(find.text('Эксперимент'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
