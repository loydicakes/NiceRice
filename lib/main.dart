// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';

// ⬇️ ADD: localization imports
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'language_controller.dart';

import 'firebase_options.dart';

// Screens
import 'pages/landingpage/landing_page.dart';
import 'pages/login/login.dart';
import 'pages/landingpage/splash_screen.dart';
import 'pages/homepage/home_page.dart';
import 'pages/signup/signup.dart';

import 'package:nice_rice/data/operation_persistence.dart';
import 'tab.dart'; // AppShell (parent Scaffold that owns the header)

// Theme controller
import 'theme_controller.dart';

final ThemeController _theme = ThemeController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // keep your one-time sync
  OperationPersistence.attachOneTimeLoginSync(clearLocalAfter: true);

  // ⬇️ ADD: load saved language choice before building the app
  await LanguageController.instance.init();

  runApp(ThemeScope(controller: _theme, child: const BootstrapApp()));
}

class BootstrapApp extends StatelessWidget {
  const BootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    // ⬇️ LISTEN to language changes so MaterialApp rebuilds when user switches language
    return AnimatedBuilder(
      animation: Listenable.merge([theme, LanguageController.instance]),
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,

          // ⬇️ Optional: make the app title localized
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx)?.appTitle ?? 'NiceRice',

          // THEMING (unchanged)
          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          themeMode: theme.mode,

          // ⬇️ ADD: localization config
          localizationsDelegates: const [
            AppLocalizations.delegate,                 // generated from ARB
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('fil'), // use 'tl' if you chose Tagalog
          ],
          locale: LanguageController.instance.locale,   // null = follow system

          // Safe fallback: if device locale unsupported, use English
          localeResolutionCallback: (device, supported) {
            final forced = LanguageController.instance.locale;
            if (forced != null) return forced;
            if (device != null) {
              for (final l in supported) {
                if (l.languageCode == device.languageCode) return l;
              }
            }
            return const Locale('en');
          },

          // Start at Splash (does guarded auth routing) — unchanged
          home: const SplashScreen(),

          // Centralized routes — unchanged
          routes: {
            '/landing': (_) => const LandingPage(),
            '/login': (_) => const LoginPage(),
            '/signup': (_) => const SignUpPage(),
            '/main': (ctx) {
              final int? initial =
                  ModalRoute.of(ctx)?.settings.arguments as int?;
              return AppShell(initialIndex: initial ?? 0);
            },
            '/home': (_) => const HomePage(), // if you still deep-link to it
          },
        );
      },
    );
  }
}
