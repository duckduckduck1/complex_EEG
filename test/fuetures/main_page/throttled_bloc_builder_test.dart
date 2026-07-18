import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/plots/throttled_bloc_builder.dart';

class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(0);

  void set(int value) => emit(value);
}

void main() {
  testWidgets('поток отсчётов не превращается в поток перестроек', (
    tester,
  ) async {
    final cubit = _CounterCubit();
    addTearDown(cubit.close);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ThrottledBlocBuilder<_CounterCubit, int>(
          bloc: cubit,
          interval: const Duration(seconds: 30),
          builder: (context, state) {
            builds++;
            return Text('$state');
          },
        ),
      ),
    );
    expect(builds, 1);

    // Двести отсчётов подряд — ровно то, что делает устройство за секунду.
    for (var i = 1; i <= 200; i++) {
      cubit.set(i);
    }
    await tester.pump();
    await tester.pump();

    expect(builds, 1, reason: 'интервал не истёк — перестраиваться не должно');
    expect(find.text('0'), findsOneWidget, reason: 'на экране первый кадр');
  });

  testWidgets('с нулевым интервалом строится на каждое состояние', (
    tester,
  ) async {
    final cubit = _CounterCubit();
    addTearDown(cubit.close);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ThrottledBlocBuilder<_CounterCubit, int>(
          bloc: cubit,
          interval: Duration.zero,
          builder: (context, state) {
            builds++;
            return Text('$state');
          },
        ),
      ),
    );

    cubit.set(1);
    cubit.set(2);
    await tester.pump();
    await tester.pump();

    expect(builds, greaterThan(1));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('после паузы больше интервала перестройка снова проходит', (
    tester,
  ) async {
    final cubit = _CounterCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: ThrottledBlocBuilder<_CounterCubit, int>(
          bloc: cubit,
          interval: const Duration(milliseconds: 20),
          builder: (context, state) => Text('$state'),
        ),
      ),
    );

    // Ограничитель смотрит на настоящие часы, поэтому и ждём по-настоящему.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    cubit.set(1);
    // Два кадра: состояние доезжает микрозадачей уже после первого.
    await tester.pump();
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
