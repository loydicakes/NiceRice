import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'language_controller.dart';

import 'firebase_options.dart';

import 'pages/landingpage/landing_page.dart';
import 'pages/login/login.dart';
import 'pages/landingpage/splash_screen.dart';
import 'pages/homepage/home_page.dart';
import 'pages/signup/signup.dart';

import 'package:nice_rice/data/operation_persistence.dart';
import 'tab.dart';

import 'theme_controller.dart';

final ThemeController _theme = ThemeController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  OperationPersistence.attachOneTimeLoginSync(clearLocalAfter: true);

  await LanguageController.instance.init();

  runApp(ThemeScope(controller: _theme, child: const BootstrapApp()));
}

class BootstrapApp extends StatelessWidget {
  const BootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([theme, LanguageController.instance]),
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,

          onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle ?? 'NiceRice',

          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          themeMode: theme.mode,

          localizationsDelegates: const [
            AppLocalizations.delegate, 
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('fil'),
          ],
          locale: LanguageController.instance.locale,

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

          home: const SplashScreen(),

          routes: {
            '/landing': (_) => const LandingPage(),
            '/login': (_) => const LoginPage(),
            '/signup': (_) => const SignUpPage(),
            '/main': (ctx) {
              final int? initial =
                  ModalRoute.of(ctx)?.settings.arguments as int?;
              return AppShell(initialIndex: initial ?? 0);
            },
            '/home': (_) => const HomePage(),
          },
        );
      },
    );
  }
}
