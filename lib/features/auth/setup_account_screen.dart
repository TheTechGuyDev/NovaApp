import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/nova_store.dart';
import '../../core/widgets/pin_pad.dart';

/// After sign-up: choose a @username, then create a 4-digit transaction PIN.
class SetupAccountScreen extends StatefulWidget {
  const SetupAccountScreen({super.key});

  @override
  State<SetupAccountScreen> createState() => _SetupAccountScreenState();
}

class _SetupAccountScreenState extends State<SetupAccountScreen> {
  final _username = TextEditingController();
  final _pinKey = GlobalKey<PinPadState>();
  Timer? _debounce;
  bool? _available;
  bool _busy = false;
  String? _firstPin;

  static final _valid = RegExp(r'^[a-z0-9_]{3,20}$');

  void _onUsername(String v) {
    _debounce?.cancel();
    setState(() => _available = null);
    final u = v.trim().toLowerCase();
    if (!_valid.hasMatch(u)) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final ok = await context.read<NovaStore>().usernameAvailable(u);
      if (mounted && _username.text.trim().toLowerCase() == u) setState(() => _available = ok);
    });
  }

  Future<void> _saveUsername() async {
    setState(() => _busy = true);
    try {
      await context.read<NovaStore>().setUsername(_username.text.trim());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('That username was just taken. Try another.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPin(String pin) async {
    if (_firstPin == null) {
      setState(() => _firstPin = pin);
      _pinKey.currentState?.clear();
      return;
    }
    if (pin != _firstPin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("PINs don't match. Start again.")));
      setState(() => _firstPin = null);
      _pinKey.currentState?.clear();
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<NovaStore>().setPin(pin);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not save PIN. Try again.')));
        setState(() => _firstPin = null);
        _pinKey.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final profile = store.profile!;
    final scheme = Theme.of(context).colorScheme;
    final needsUsername = profile.username == null;

    return Scaffold(
      appBar: AppBar(
        actions: [TextButton(onPressed: store.signOut, child: const Text('Sign out'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text('Step ${needsUsername ? 1 : 2} of 2',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  needsUsername
                      ? 'Choose your NOVA tag'
                      : (_firstPin == null ? 'Create transaction PIN' : 'Confirm your PIN'),
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  needsUsername
                      ? 'Friends can send you money and crypto instantly with your @tag.'
                      : 'You will use this 4-digit PIN to approve every transaction.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                if (needsUsername) ...[
                  TextField(
                    controller: _username,
                    onChanged: _onUsername,
                    autocorrect: false,
                    decoration: InputDecoration(
                      prefixText: '@ ',
                      labelText: 'Username',
                      helperText: '3 to 20 characters: letters, numbers, underscore',
                      suffixIcon: _available == null
                          ? null
                          : Icon(
                              _available! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              color: _available! ? scheme.primary : scheme.error,
                            ),
                    ),
                  ),
                  if (_available == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Username is taken', style: TextStyle(color: scheme.error)),
                    ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: (_available == true && !_busy) ? _saveUsername : null,
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Continue'),
                  ),
                ] else ...[
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  PinPad(key: _pinKey, onCompleted: _onPin),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
