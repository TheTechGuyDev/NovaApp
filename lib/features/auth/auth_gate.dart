import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/nova_store.dart';
import '../onboarding/onboarding_screen.dart';
import '../selfcustody/self_custody.dart';
import '../shell/main_shell.dart';
import 'setup_account_screen.dart';

/// Routes the user based on session + profile completeness:
/// no session -> onboarding/sign in, incomplete -> setup, else -> app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        _loadedFor = null;
        context.read<SelfCustodyStore>().clear();
      }
      _maybeLoad();
      if (mounted) setState(() {});
    });
    _maybeLoad();
  }

  void _maybeLoad() {
    final uid = sb.auth.currentUser?.id;
    if (uid != null && _loadedFor != uid) {
      _loadedFor = uid;
      context.read<NovaStore>().loadAll();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = sb.auth.currentSession;
    if (session == null) return const OnboardingScreen();

    final store = context.watch<NovaStore>();
    final profile = store.profile;

    if (profile == null) {
      if (store.error != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 40),
                  const SizedBox(height: 12),
                  const Text('Could not load your account'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: store.loadAll, child: const Text('Retry')),
                  TextButton(onPressed: store.signOut, child: const Text('Sign out')),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!profile.isSetupComplete) return const SetupAccountScreen();
    return const MainShell();
  }
}
