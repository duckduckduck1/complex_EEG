import 'package:flutter/material.dart';

/// Единая тёмная тема приложения — «Осциллограф» (cyan-акцент, Material 3).
///
/// Имя экспорта `theme` сохранено: используется в `main_app.dart`
/// (`MaterialApp(theme: theme)`).
final ThemeData theme = _buildOscilloscopeTheme();

// Базовые цвета палитры «Осциллограф».
const Color _bg = Color(0xFF101318); // фон / scaffold
const Color _surface = Color(0xFF171B22); // карточка
const Color _appBar = Color(0xFF181C24); // аппбар / навигация
const Color _outline = Color(0xFF242A34); // границы / разделители
const Color _onSurface = Color(0xFFEEF2F6); // основной текст
const Color _muted = Color(0xFF8B95A3); // приглушённый текст

const Color _primary = Color(0xFF2EE6C8); // cyan-акцент
const Color _onPrimary = Color(0xFF002019); // тёмный текст на cyan
const Color _secondary = Color(0xFF9B7CFF); // violet
const Color _error = Color(0xFFFF5C6C);

ThemeData _buildOscilloscopeTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: _primary,
    onPrimary: _onPrimary,
    secondary: _secondary,
    error: _error,
    surface: _surface,
    onSurface: _onSurface,
    onSurfaceVariant: _muted,
    outline: _outline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: _bg,
    dividerColor: _outline,
    appBarTheme: const AppBarThemeData(
      backgroundColor: _appBar,
      foregroundColor: _onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: _onSurface,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: const CardThemeData(
      color: _surface,
      elevation: 0,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: _outline),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorColor: _primary,
      labelColor: _primary,
      unselectedLabelColor: _muted,
    ),
    dividerTheme: const DividerThemeData(color: _outline),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: _appBar,
      indicatorColor: _primary,
      selectedIconTheme: IconThemeData(color: _onPrimary),
      unselectedIconTheme: IconThemeData(color: _muted),
      selectedLabelTextStyle: TextStyle(
        color: _primary,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: _muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _appBar,
      indicatorColor: _primary,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected)
                ? const IconThemeData(color: _onPrimary)
                : const IconThemeData(color: _muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected)
                ? const TextStyle(color: _primary, fontWeight: FontWeight.w600)
                : const TextStyle(color: _muted),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: _onPrimary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: _onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        side: const BorderSide(color: _outline),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _primary,
      foregroundColor: _onPrimary,
    ),
    // Узкие экраны используют legacy BottomNavigationBar (Material 2), который
    // не читает navigationBarTheme — задаём его отдельно, чтобы выбранный
    // раздел тоже подсвечивался cyan-акцентом.
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _appBar,
      selectedItemColor: _primary,
      unselectedItemColor: _muted,
      type: BottomNavigationBarType.fixed,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _surface,
      contentTextStyle: TextStyle(color: _onSurface),
      actionTextColor: _primary,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: const <ThemeExtension<dynamic>>[EegPalette.oscilloscope],
  );
}

/// Палитра цветов графиков ЭЭГ как `ThemeExtension`.
///
/// Это ИСТОЧНИК цветов графиков (сигнал, спектр, ритмы, сетка) на будущее.
/// В текущем слайсе к коду графиков (`*_scafold.dart`, `eeg_widget.dart`)
/// НЕ подключается — только объявляется и регистрируется в `theme.extensions`.
/// Перекраска графиков под эту палитру — отдельный слайс.
@immutable
class EegPalette extends ThemeExtension<EegPalette> {
  const EegPalette({
    required this.signal,
    required this.spectrum,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.grid,
    required this.success,
  });

  /// Цвет линии живого / сохранённого сигнала.
  final Color signal;

  /// Цвет спектра (FFT).
  final Color spectrum;

  /// Ритм delta.
  final Color delta;

  /// Ритм theta.
  final Color theta;

  /// Ритм alpha.
  final Color alpha;

  /// Ритм beta.
  final Color beta;

  /// Сетка графиков.
  final Color grid;

  /// Успех / положительный статус.
  final Color success;

  /// Палитра «Осциллограф» — эталонный набор цветов графиков.
  static const EegPalette oscilloscope = EegPalette(
    signal: Color(0xFF2EE6C8),
    spectrum: Color(0xFF9B7CFF),
    delta: Color(0xFF4AA3FF),
    theta: Color(0xFF33D17A),
    alpha: Color(0xFFF0A020),
    beta: Color(0xFFFF5C6C),
    grid: Color(0xFF232833),
    success: Color(0xFF33D17A),
  );

  @override
  EegPalette copyWith({
    Color? signal,
    Color? spectrum,
    Color? delta,
    Color? theta,
    Color? alpha,
    Color? beta,
    Color? grid,
    Color? success,
  }) {
    return EegPalette(
      signal: signal ?? this.signal,
      spectrum: spectrum ?? this.spectrum,
      delta: delta ?? this.delta,
      theta: theta ?? this.theta,
      alpha: alpha ?? this.alpha,
      beta: beta ?? this.beta,
      grid: grid ?? this.grid,
      success: success ?? this.success,
    );
  }

  @override
  EegPalette lerp(ThemeExtension<EegPalette>? other, double t) {
    if (other is! EegPalette) {
      return this;
    }
    return EegPalette(
      signal: Color.lerp(signal, other.signal, t)!,
      spectrum: Color.lerp(spectrum, other.spectrum, t)!,
      delta: Color.lerp(delta, other.delta, t)!,
      theta: Color.lerp(theta, other.theta, t)!,
      alpha: Color.lerp(alpha, other.alpha, t)!,
      beta: Color.lerp(beta, other.beta, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}
