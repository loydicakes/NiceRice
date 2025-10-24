import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 


class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void setDark(bool value) {
    final next = value ? ThemeMode.dark : ThemeMode.light;
    if (next != _mode) {
      _mode = next;
      notifyListeners();
    }
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found. Wrap your app with ThemeScope.');
    return scope!.notifier!;
  }
}


class Brand {
  static const Color bgGrey = Color(0xFFF5F5F5);
  static const Color darkGreen = Color(0xFF2F6F4F);
  static const Color tileBorder = Color(0xFF7C7C7C);
  static const Color progressBgLight = Color(0xFFE5EBE6);

  static const Color darkBg = Color(0xFF0E1311);
  static const Color darkSurface = Color(0xFF1A201D);
  static const Color darkTileBorder = Color(0xFF404A45);
  static const Color progressBgDark = Color(0xFF243329);
}

class AppThemes {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Brand.darkGreen,
        brightness: Brightness.light,
      ).copyWith(
        background: Brand.bgGrey,
        surface: Colors.white,
        surfaceVariant: Brand.bgGrey,
        outline: Brand.tileBorder,              
        tertiaryContainer: Brand.progressBgLight, 
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: Brand.bgGrey,
      appBarTheme: const AppBarTheme(
        backgroundColor: Brand.bgGrey,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.darkGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Brand.darkGreen,
        linearTrackColor: Brand.progressBgLight,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Brand.darkGreen,
        brightness: Brightness.dark,
      ).copyWith(
        background: Brand.darkBg,
        surface: Brand.darkSurface,
        surfaceVariant: const Color(0xFF141A17),
        outline: Brand.darkTileBorder,
        tertiaryContainer: Brand.progressBgDark,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: Brand.darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Brand.darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Brand.darkSurface,
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.darkGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Brand.darkGreen,
        linearTrackColor: Brand.progressBgDark,
      ),
    );
  }
}

extension NiceColors on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;

  Color get brand => cs.primary;

  Color get tileFill => cs.surfaceVariant;

  Color get tileStroke => cs.outline;

  Color get progressTrack => cs.tertiaryContainer;

  Color get appBarBg =>
      Theme.of(this).appBarTheme.backgroundColor ??
      Theme.of(this).scaffoldBackgroundColor;
}
