import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_shell.dart';
import 'core/config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

/// NOVA Admin: separate web entry point, served at /NovaApp/admin/.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  final theme = ThemeController();
  await theme.load();
  runApp(ChangeNotifierProvider.value(value: theme, child: const NovaAdminApp()));
}

class NovaAdminApp extends StatelessWidget {
  const NovaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return MaterialApp(
      title: 'NOVA Admin',
      debugShowCheckedModeBanner: false,
      theme: _compact(AppTheme.light),
      darkTheme: _compact(AppTheme.dark),
      themeMode: mode,
      home: const AdminGate(),
    );
  }
}

/// The customer app uses full-width buttons; the dashboard needs inline ones.
ThemeData _compact(ThemeData t) => t.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: t.filledButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
        ),
      ),
    );
