import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RtEegDataBloc bloc;

  setUp(() => bloc = RtEegDataBloc(250));
  tearDown(() => bloc.close());

  int windowLength() {
    final state = bloc.state;
    return state is DataUpdated ? state.newData.length : 0;
  }

  test('пачка отсчётов даёт одно окно графика на всю пачку', () async {
    bloc.add(NewEegSamplesReceived(samples: const [1, 2, 3]));
    await pumpEventQueue();

    // Одно окно, длиной во всю пачку — не по emit на отсчёт.
    expect(bloc.state, isA<DataUpdated>());
    expect(windowLength(), 3);

    bloc.add(NewEegSamplesReceived(samples: const [4, 5]));
    await pumpEventQueue();
    expect(windowLength(), 5);
  });

  test('пустая пачка не меняет состояние', () async {
    bloc.add(NewEegSamplesReceived(samples: const []));
    await pumpEventQueue();
    expect(bloc.state, isA<DataInitial>());
  });

  test('сброс очищает окно графика', () async {
    bloc.add(NewEegSamplesReceived(samples: const [1, 2, 3]));
    await pumpEventQueue();
    expect(windowLength(), 3);

    bloc.add(RtEegResetRequested());
    await pumpEventQueue();
    expect(bloc.state, isA<DataInitial>());
  });
}
