import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/views/main_page_view.dart';
import 'package:iot/fuetures/ble_page/views/ble_page_view.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Adaptive Navigation',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0; // Текущий выбранный раздел
  final List<Widget> _pages = [
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

    return Scaffold(
      body: Row(
        children: [
          // Боковая панель (NavigationRail) — только для широких экранов
          if (isWideScreen)
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
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
          Expanded(child: IndexedStack(index: _currentIndex, children: _pages)),
        ],
      ),
      // Нижний бар (для мобилок)
      bottomNavigationBar:
          isWideScreen
              ? null // На широких экранах BottomBar не нужен
              : BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
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
  }
}
