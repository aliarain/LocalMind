import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'features/onboarding/splash_screen.dart';

class LocalMindApp extends StatelessWidget {
  const LocalMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
