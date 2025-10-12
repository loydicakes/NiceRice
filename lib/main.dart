// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Screens
import 'pages/landingpage/landing_page.dart';
import 'pages/login/login.dart';
import 'pages/landingpage/splash_screen.dart';
import 'pages/homepage/home_page.dart';
import 'pages/signup/signup.dart';

import 'package:nice_rice/data/operation_persistence.dart';
import 'tab.dart'; // AppShell (parent Scaffold that owns the header)
import 'theme_controller.dart';

// NEW
import 'services/route_logger.dart';

final ThemeController _theme = ThemeController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  OperationPersistence.attachOneTimeLoginSync(clearLocalAfter: true);
  runApp(ThemeScope(controller: _theme, child: const BootstrapApp()));
}

class BootstrapApp extends StatelessWidget {
  const BootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return AnimatedBuilder(
      animation: theme,
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          themeMode: theme.mode,

          // Start at Splash (it will now decide first-launch / auth / last-route)
          home: const SplashScreen(),

          // Save last route automatically:
          navigatorObservers: [RouteLogger()],

          // Centralized routes
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
