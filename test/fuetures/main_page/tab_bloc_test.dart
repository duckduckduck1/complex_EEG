import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/tabs/bloc/tab_bloc.dart';

import '../../support/device_view_session_fakes.dart';

void main() {
  testWidgets('active recording tab is not closed', (tester) async {
    final session = createTestViewSession();
    final recordingBloc = session.recordingBloc;
    final tabBloc = TabBloc(vsync: tester);
    // Сессию закрывает TabBloc вместе с вкладкой — руками её тут не трогаем.
    addTearDown(tabBloc.close);

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

    tabBloc.add(
      NewTabAdded(
        newTab: const Text('recording'),
        content: const SizedBox(key: Key('recording-tab')),
        session: session,
      ),
    );
    tabBloc.add(
      NewTabAdded(
        newTab: const Text('idle'),
        content: const SizedBox(key: Key('idle-tab')),
      ),
    );
    await tester.pump();

    tabBloc.add(CloseTab(0));
    await tester.pump();

    expect(recordingBloc.state.status, RecordingStatus.recording);
    expect(tabBloc.state.tabs, hasLength(2));
    expect(tabBloc.state.tabContents.first.key, const Key('recording-tab'));
  });

  testWidgets('закрытие вкладки освобождает её сессию', (tester) async {
    // Владение переехало из виджета в TabBloc, значит и освобождать теперь его
    // забота: иначе каждая закрытая вкладка оставляла бы жить мост от BLE
    // к графикам и bloc записи.
    final session = createTestViewSession();
    final tabBloc = TabBloc(vsync: tester);
    addTearDown(tabBloc.close);
    addTearDown(session.connection.close);

    tabBloc.add(
      NewTabAdded(
        newTab: const Text('Мышь 1'),
        content: const SizedBox(),
        session: session,
      ),
    );
    await tester.pump();
    expect(session.recordingBloc.isClosed, isFalse);

    tabBloc.add(CloseTab(0));
    await tester.pump();

    expect(tabBloc.state.tabs, isEmpty);
    // Проверяем сам факт освобождения, а не закрытость bloc'ов: закрытие
    // асинхронное и под фейковым временем testWidgets не доезжает. Что оно
    // действительно закрывает — проверяет тест ниже, через runAsync.
    expect(session.isDisposed, isTrue);
    expect(
      session.connection.isClosed,
      isFalse,
      reason: 'подключением владеет SessionsCubit, вкладка его не трогает',
    );
  });

  testWidgets('закрытие TabBloc освобождает сессии открытых вкладок', (
    tester,
  ) async {
    final session = createTestViewSession();
    final tabBloc = TabBloc(vsync: tester);
    addTearDown(session.connection.close);

    tabBloc.add(
      NewTabAdded(
        newTab: const Text('Мышь 1'),
        content: const SizedBox(),
        session: session,
      ),
    );
    await tester.pump();

    await tester.runAsync(tabBloc.close);

    expect(session.recordingBloc.isClosed, isTrue);
    expect(session.rtEegDataBloc.isClosed, isTrue);
  });
}
