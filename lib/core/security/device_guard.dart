import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Device integrity: detects rooted Android / jailbroken iOS devices and
/// turns on screenshot and screen-recording blocking.
///
/// Live mode: a compromised device is blocked and screens are protected.
/// Sandbox mode: testers see a warning and can still take screenshots.
class DeviceIntegrity {
  DeviceIntegrity._();
  static const _channel = MethodChannel('nova/security');

  static bool get _native =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<List<String>> compromiseReasons() async {
    if (!_native) return const [];
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('integrity');
      return (r ?? const []).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setSecureScreen(bool on) async {
    if (!_native) return;
    try {
      await _channel.invokeMethod('secureScreen', {'on': on});
    } catch (_) {}
  }

  /// Environment from the server (admin can switch to live without a release).
  static Future<String> environment() async {
    try {
      final c = await Supabase.instance.client.rpc('public_config');
      return (c is Map ? c['environment'] : null)?.toString() ?? AppConfig.environment;
    } catch (_) {
      return AppConfig.environment;
    }
  }
}

class DeviceGuard extends StatefulWidget {
  const DeviceGuard({super.key, required this.child});
  final Widget child;

  @override
  State<DeviceGuard> createState() => _DeviceGuardState();
}

class _DeviceGuardState extends State<DeviceGuard> {
  List<String> _reasons = const [];
  bool _live = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final results = await Future.wait<dynamic>([
      DeviceIntegrity.compromiseReasons(),
      DeviceIntegrity.environment(),
    ]);
    final reasons = results[0] as List<String>;
    final live = results[1] == 'live';
    await DeviceIntegrity.setSecureScreen(live);
    if (mounted) setState(() { _reasons = reasons; _live = live; });
  }

  @override
  Widget build(BuildContext context) {
    if (_reasons.isEmpty || _dismissed) return widget.child;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gpp_bad_rounded, size: 72, color: theme.colorScheme.error),
              const SizedBox(height: 20),
              Text(
                defaultTargetPlatform == TargetPlatform.iOS ? 'Jailbroken device detected' : 'Rooted device detected',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _live
                    ? 'For your safety, NOVA can\'t run on a device whose security has been modified. '
                        'Please use an unmodified phone to access your account.'
                    : 'This device\'s security has been modified, so other apps could read your data. '
                        'NOVA will block this device in live mode.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (!_live) ...[
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => setState(() => _dismissed = true),
                  child: const Text('Continue (test mode)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
