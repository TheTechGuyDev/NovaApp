import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = ThemeController();
  await theme.load();
  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('nova_onboarded') ?? false;

  runApp(
    ChangeNotifierProvider.value(
      value: theme,
      child: NovaApp(onboarded: onboarded),
    ),
  );
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key, required this.onboarded});
  final bool onboarded;

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return MaterialApp(
      title: 'NOVA Finance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: child!,
        );
      },
      home: onboarded ? const MainShell() : const OnboardingScreen(),
    );
  }
}
