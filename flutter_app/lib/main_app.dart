import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iot/features/devices/application/sessions_cubit.dart';
import 'package:iot/features/devices/domain/ble_adapter.dart';
import 'package:iot/features/navigation/navigation_cubit.dart';
import 'package:iot/fuetures/main_layout/views/main_layout_view.dart';
import 'package:iot/platform/ble/flutter_blue_plus_adapter.dart';
import 'package:iot/theme.dart';

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
