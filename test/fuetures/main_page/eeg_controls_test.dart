import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/domain/annotation_models.dart';
import 'package:eeg_app_max30003_stm32/features/annotation/presentation/recording_annotation_dialog.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_ports.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/eeg_widget_settings_bar/eeg_settings_bar.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/filter_settings/exp_widget.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/recording/recording_reservation_strip.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

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
    var startPressed = false;
    final recordingBloc = _createRecordingBloc();
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    await tester.pumpWidget(
      wrap(
        RecordingReservationStrip(
          recordingBloc: recordingBloc,
          onStartPressed: () => startPressed = true,
        ),
        width: 320,
      ),
    );

    expect(
      find.byKey(const Key('eeg-recording-reservation-strip')),
      findsOneWidget,
    );
    expect(find.text('Запись эксперимента не идёт'), findsOneWidget);
    expect(find.text('Начать эксперимент'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Начать эксперимент'));
    await tester.pump();

    expect(startPressed, isTrue);
  });

  testWidgets('recording strip shows reconnect controls after BLE disconnect', (
    tester,
  ) async {
    var reconnectPressed = false;
    final recordingBloc = _createRecordingBloc();
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();
    recordingBloc.add(const RecordingConnectionLost());
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        RecordingReservationStrip(
          recordingBloc: recordingBloc,
          onStartPressed: () {},
          onReconnectPressed: () => reconnectPressed = true,
        ),
        width: 360,
      ),
    );

    expect(find.text('Связь потеряна, запись на паузе'), findsOneWidget);
    expect(find.text('Переподключиться'), findsOneWidget);
    expect(find.text('Завершить'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Переподключиться'));
    await tester.pump();
    expect(reconnectPressed, isTrue);

    await tester.tap(find.text('Завершить'));
    await tester.pump();
    await tester.pump();
    expect(recordingBloc.state.status, RecordingStatus.stopped);
  });

  testWidgets('recording strip exposes controls and annotation pickers', (
    tester,
  ) async {
    final recordingBloc = _createRecordingBloc();
    var annotationsPressed = false;
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        RecordingReservationStrip(
          recordingBloc: recordingBloc,
          onStartPressed: () {},
          onAnnotationsPressed: () => annotationsPressed = true,
        ),
        width: 900,
      ),
    );

    expect(find.text('Свет вкл'), findsOneWidget);
    expect(find.text('ШИМ 50'), findsOneWidget);
    expect(find.text('Метка'), findsOneWidget);
    expect(find.text('Событие'), findsOneWidget);
    expect(find.text('Список'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Свет вкл'));
    await tester.pump();
    await tester.pump();

    expect(recordingBloc.state.fbmOn, isTrue);
    expect(find.text('Свет выкл'), findsOneWidget);

    await tester.tap(find.text('Список'));
    await tester.pump();
    expect(annotationsPressed, isTrue);
  });

  testWidgets('state picker starts a state and toggles the button to stop', (
    tester,
  ) async {
    final recordingBloc = _createRecordingBloc();
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        RecordingReservationStrip(
          recordingBloc: recordingBloc,
          onStartPressed: () {},
        ),
        width: 900,
      ),
    );

    // Выкатываем список состояний и запускаем «Спит».
    await tester.tap(find.text('Метка'));
    await tester.pumpAndSettle();
    expect(find.text('Спит'), findsOneWidget);

    await tester.tap(find.text('Спит'));
    await tester.pumpAndSettle();

    expect(recordingBloc.state.activeDraftLabel, isNotNull);
    expect(recordingBloc.state.activeDraftLabel!.labelTypeId, 'sleep');
    // Кнопка «Метка» превратилась в активную метку с таймером.
    expect(find.text('Метка'), findsNothing);
    expect(find.textContaining('Спит'), findsOneWidget);
  });

  testWidgets('event picker adds a point event on one tap', (tester) async {
    final recordingBloc = _createRecordingBloc();
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();
    recordingBloc.add(const RecordingSamplesReceived([1, 2, 3]));
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        RecordingReservationStrip(
          recordingBloc: recordingBloc,
          onStartPressed: () {},
        ),
        width: 900,
      ),
    );

    await tester.tap(find.text('Событие'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вздрогнула'));
    await tester.pumpAndSettle();

    expect(recordingBloc.state.labels, hasLength(1));
    expect(recordingBloc.state.labels.single.kind, AnnotationKind.event);
    expect(recordingBloc.state.labels.single.labelTypeId, 'startle');
  });

  testWidgets('ручное добавление метки по времени валидирует интервал', (
    tester,
  ) async {
    final recordingBloc = _createRecordingBloc();
    addTearDown(() async {
      if (!recordingBloc.isClosed) {
        await recordingBloc.close();
      }
    });

    recordingBloc.add(
      const RecordingStartRequested(
        RecordingStartConfig(
          rootDirectory: 'memory-root',
          pwmLevel: 50,
          displayName: 'Мышь 1',
        ),
      ),
    );
    await tester.pump();
    // 10 секунд записи (2500 отсчётов при 250 Гц), чтобы ввод времени имел смысл.
    recordingBloc.add(RecordingSamplesReceived(List<int>.filled(2500, 1)));
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        BlocProvider<RecordingBloc>.value(
          value: recordingBloc,
          child: const RecordingAnnotationDialog(),
        ),
        width: 760,
      ),
    );

    final noteField = find.byKey(const Key('recording-annotation-note-field'));
    final startField = find.byKey(
      const Key('recording-annotation-manual-start-field'),
    );
    final endField = find.byKey(
      const Key('recording-annotation-manual-end-field'),
    );
    final addButton = find.byKey(const Key('recording-annotation-add-manual'));

    await tester.enterText(noteField, 'заметка оператора');
    // Конец раньше начала — ошибка, метка не добавляется.
    await tester.enterText(startField, '00:05');
    await tester.enterText(endField, '00:02');
    await tester.tap(addButton);
    await tester.pump();

    expect(find.text('Конец должен быть позже начала'), findsOneWidget);
    expect(recordingBloc.state.labels, isEmpty);

    // Корректный интервал 00:02–00:05 — добавляется метка-состояние.
    await tester.enterText(startField, '00:02');
    await tester.enterText(endField, '00:05');
    await tester.tap(addButton);
    await tester.pump();

    expect(recordingBloc.state.labels, hasLength(1));
    expect(recordingBloc.state.labels.single.kind, AnnotationKind.state);
    expect(recordingBloc.state.labels.single.note, 'заметка оператора');
  });
}

RecordingBloc _createRecordingBloc() {
  return RecordingBloc(
    storage: _MemoryExperimentStorage(),
    filterFactory: const PassThroughStreamingFilterFactory(),
    idGenerator: const _FixedIdGenerator(),
    fbmTransport: const _FakeFbmTransport(),
  );
}

class _MemoryExperimentStorage implements ExperimentStorage {
  @override
  Future<void> createExperiment({
    required String rootDirectory,
    required String experimentId,
    required String folderName,
  }) async {}

  @override
  Future<void> appendSamples({
    required List<int> filtered,
    required List<int> raw,
  }) async {}

  @override
  Future<void> appendJournal(
    Map<String, Object?> event, {
    bool flush = false,
  }) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> writeExperimentJson(Map<String, Object?> experimentJson) async {}

  @override
  Future<void> close() async {}
}

class _FixedIdGenerator implements ExperimentIdGenerator {
  const _FixedIdGenerator();

  @override
  String nextId() => 'exp_controls_test';
}

class _FakeFbmTransport implements FbmTransport {
  const _FakeFbmTransport();

  @override
  Future<bool> setLed({required bool on, required int pwmByte}) async => true;
}
