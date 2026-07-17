import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eeg_app_max30003_stm32/features/navigation/navigation_cubit.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/views/main_page_view.dart';
import 'package:eeg_app_max30003_stm32/fuetures/ble_page/views/ble_page_view.dart';

/// Раскладка приложения: боковая/нижняя навигация переключает раздел.
///
/// Выбранный раздел — сценарное состояние, поэтому живёт в [NavigationCubit]
/// (docs/flutter_app/bloc.md), а не в `setState`; `PageStorage`/`IndexedStack`
/// остаются локальными деталями раскладки виджета.
class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  static final List<Widget> _pages = [
    PageStorage(bucket: PageStorageBucket(), child: MainPage()),
    PageStorage(bucket: PageStorageBucket(), child: const BlePageView()),
    PageStorage(
      bucket: PageStorageBucket(),
      child: Center(
        child: Text('Настройки ⚙️', style: TextStyle(fontSize: 24)),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen =
        MediaQuery.of(context).size.width >= 600; // Порог для переключения

    return BlocBuilder<NavigationCubit, NavigationState>(
      builder: (context, state) {
        final currentIndex = state.sectionIndex;

        return Scaffold(
          body: Row(
            children: [
              // Боковая панель (NavigationRail) — только для широких экранов
              if (isWideScreen)
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: (index) {
                    context.read<NavigationCubit>().selectSection(index);
                  },
                  labelType:
                      NavigationRailLabelType
                          .none, // Показывать текст всегда или только у выбранного
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home),
                      label: Text('Главная'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.devices),
                      label: Text('Устройства'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('Настройки'),
                    ),
                  ],
                ),
              // Основной контент
              Expanded(
                child: IndexedStack(index: currentIndex, children: _pages),
              ),
            ],
          ),
          // Нижний бар (для мобилок)
          bottomNavigationBar:
              isWideScreen
                  ? null // На широких экранах BottomBar не нужен
                  : BottomNavigationBar(
                    currentIndex: currentIndex,
                    onTap:
                        (index) => context
                            .read<NavigationCubit>()
                            .selectSection(index),
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home),
                        label: 'Главная',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.devices),
                        label: 'Устройства',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings),
                        label: 'Настройки',
                      ),
                    ],
                  ),
        );
      },
    );
  }
}
