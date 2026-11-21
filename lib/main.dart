import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/data/nova_store.dart';
import 'core/security/device_guard.dart';
import 'core/security/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/selfcustody/self_custody.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    // Mobile: session lives in the secure keystore. Web: browser storage.
    authOptions: kIsWeb
        ? const FlutterAuthClientOptions()
        : FlutterAuthClientOptions(
            localStorage: SecureSessionStorage(
              persistSessionKey: 'sb-${Uri.parse(AppConfig.supabaseUrl).host.split('.').first}-auth-token',
            ),
          ),
  );
  final theme = ThemeController();
  await theme.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider(create: (_) => NovaStore()),
        ChangeNotifierProvider(create: (_) => SelfCustodyStore()),
      ],
      child: const NovaApp(),
    ),
  );
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

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
      home: const DeviceGuard(child: AuthGate()),
    );
  }
}
