import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/devices/application/sessions_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/devices/domain/ble_adapter.dart';
import 'package:eeg_app_max30003_stm32/features/navigation/navigation_cubit.dart';
import 'package:eeg_app_max30003_stm32/features/recording/application/recording_bloc_factory.dart';
import 'package:eeg_app_max30003_stm32/features/recording/data/file_recording_bloc_factory.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_layout/views/main_layout_view.dart';
import 'package:eeg_app_max30003_stm32/platform/ble/flutter_blue_plus_adapter.dart';
import 'package:eeg_app_max30003_stm32/theme.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: theme,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BleAdapter>(
            create: (_) => FlutterBluePlusAdapter(),
          ),
          RepositoryProvider<RecordingBlocFactory>(
            create: (_) => const FileRecordingBlocFactory(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionsCubit>(
              create:
                  (context) =>
                      SessionsCubit(adapter: context.read<BleAdapter>()),
            ),
            BlocProvider<NavigationCubit>(create: (_) => NavigationCubit()),
          ],
          child: const MainLayout(),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
