import 'package:flutter/material.dart';

import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/app_theme.dart';

void main() {
  runApp(const MasakinApp());
}

class MasakinApp extends StatelessWidget {
  const MasakinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MasakIn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: SplashScreen.routeName,
      routes: {
        SplashScreen.routeName: (_) => const SplashScreen(),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        MainScreen.routeName: (_) => const MainScreen(),
      },
    );
  }
}
