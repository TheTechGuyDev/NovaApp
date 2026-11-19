import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/nova_widgets.dart';
import 'admin_common.dart';
import 'admin_integrations.dart';
import 'admin_pages.dart';

/// Session + staff role check. Non-staff accounts are signed out.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  StreamSubscription<AuthState>? _sub;
  List<String>? _roles;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = adb.auth.onAuthStateChange.listen((_) => _check());
    _check();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (adb.auth.currentSession == null) {
      if (mounted) setState(() => _roles = null);
      return;
    }
    try {
      final r = List<String>.from(await arpc('my_roles') as List);
      if (mounted) setState(() => _roles = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (adb.auth.currentSession == null) return const AdminLogin();
    if (_roles == null) {
      return Scaffold(body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()));
    }
    if (_roles!.every((r) => r == 'user')) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline_rounded, size: 44),
              const SizedBox(height: 12),
              const Text('This account has no admin access', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => adb.auth.signOut(), child: const Text('Sign out')),
            ]),
          ),
        ),
      );
    }
    return AdminShell(roles: _roles!);
  }
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await adb.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: NovaCard(
              padding: const EdgeInsets.all(28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/brand/nova_icon.png', width: 44, height: 44),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('NOVA Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    Text('Staff access only', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: _hide,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section {
  const _Section(this.label, this.icon, this.builder, this.roles);
  final String label;
  final IconData icon;
  final Widget Function() builder;
  final List<String> roles; // any of these (super_admin always allowed)
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.roles});
  final List<String> roles;
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  late final List<_Section> _sections = [
    _Section('Overview', Icons.dashboard_rounded, () => const OverviewPage(), const ['*']),
    _Section('Users', Icons.people_alt_rounded, () => const UsersPage(),
        const ['support', 'compliance', 'banking_ops', 'risk', 'tech', 'finance']),
    _Section('Transactions', Icons.receipt_long_rounded, () => const TransactionsPage(),
        const ['support', 'compliance', 'banking_ops', 'crypto_ops', 'risk', 'finance', 'treasury']),
    _Section('Crypto Ops', Icons.currency_bitcoin_rounded, () => const CryptoOpsPage(),
        const ['crypto_ops', 'treasury', 'finance']),
    _Section('Exchange', Icons.candlestick_chart_rounded, () => const ExchangeAdminPage(), const ['exchange_ops']),
    _Section('Finance', Icons.account_balance_rounded, () => const FinancePage(), const ['finance', 'treasury']),
    _Section('Settings', Icons.tune_rounded, () => const SettingsPage(), const ['finance']),
    _Section('Integrations', Icons.key_rounded, () => const IntegrationsPage(), const ['tech']),
    _Section('Audit Log', Icons.history_rounded, () => const AuditPage(), const ['compliance', 'tech']),
  ];

  List<_Section> get _visible => _sections
      .where((s) =>
          widget.roles.contains('super_admin') || s.roles.contains('*') || s.roles.any(widget.roles.contains))
      .toList();

  @override
  Widget build(BuildContext context) {
    final sections = _visible;
    final current = sections[_index.clamp(0, sections.length - 1)];
    final wide = isWide(context);
    final theme = context.watch<ThemeController>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/brand/nova_icon.png', width: 34, height: 34)),
        const SizedBox(width: 10),
        const Text('NOVA Admin', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
    );

    Widget navList({VoidCallback? onPicked}) => ListView(
          padding: EdgeInsets.zero,
          children: [
            header,
            for (var i = 0; i < sections.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: ListTile(
                  dense: true,
                  selected: i == _index,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(sections[i].icon, size: 20),
                  title: Text(sections[i].label, style: const TextStyle(fontWeight: FontWeight.w500)),
                  onTap: () {
                    setState(() => _index = i);
                    onPicked?.call();
                  },
                ),
              ),
            const Divider(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListTile(
                dense: true,
                leading: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 20),
                title: Text(dark ? 'Light mode' : 'Dark mode'),
                onTap: () => theme.setMode(dark ? ThemeMode.light : ThemeMode.dark),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.logout_rounded, size: 20),
                title: const Text('Sign out'),
                subtitle: Text(adb.auth.currentUser?.email ?? '', style: const TextStyle(fontSize: 11)),
                onTap: () => adb.auth.signOut(),
              ),
            ),
          ],
        );

    if (wide) {
      return Scaffold(
        body: Row(children: [
          SizedBox(
            width: 250,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(child: navList()),
            ),
          ),
          VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outline),
          Expanded(child: KeyedSubtree(key: ValueKey(current.label), child: current.builder())),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('NOVA Admin'), centerTitle: false),
      drawer: Builder(
        builder: (ctx) => Drawer(child: SafeArea(child: navList(onPicked: () => Navigator.of(ctx).pop()))),
      ),
      body: KeyedSubtree(key: ValueKey(current.label), child: current.builder()),
    );
  }
}
