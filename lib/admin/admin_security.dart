import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'admin_common.dart';

/// Security events: honeypot hits, PIN and login lockouts, rate limiting,
/// KYC identity reuse. Accounts frozen by a honeypot can be restored here.
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await arpc('admin_security_events', {'_limit': 500}) as List);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _sevColor(String s) => switch (s) {
        'critical' => AppColors.danger,
        'high' => AppColors.warning,
        'medium' => Colors.blueGrey,
        _ => Colors.grey,
      };

  String _label(String kind) {
    if (kind.startsWith('honeypot:')) return 'Honeypot: ${kind.substring(9).replaceAll('_', ' ')}';
    return switch (kind) {
      'pin_lockout' => 'PIN locked (5 wrong PINs)',
      'login_lockout' => 'Login locked (5 wrong passwords)',
      'rate_limited' => 'Rate limited',
      'phone_enumeration' => 'Phone number scraping',
      'kyc_identity_reuse' => 'BVN/NIN used by another account',
      _ => kind.replaceAll('_', ' '),
    };
  }

  Future<void> _unfreeze(Map<String, dynamic> e) async {
    final ok = await confirm(context, 'Restore account?',
        'Set ${e['email'] ?? 'this user'} back to active. Only do this after confirming the activity was safe.',
        ok: 'Restore');
    if (!ok) return;
    try {
      await arpc('admin_set_user_status', {'_id': e['user_id'], '_status': 'active', '_reason': 'Reviewed security event ${e['id']}'});
      if (mounted) toast(context, 'Account restored');
    } catch (err) {
      if (mounted) toast(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final day = _rows.where((r) => DateTime.tryParse('${r['created_at']}')?.toLocal().isAfter(since) ?? false).toList();
    final shown = _filter == 'all' ? _rows : _rows.where((r) => r['severity'] == _filter).toList();

    return AdminPage(
      title: 'Security',
      onRefresh: _load,
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          StatGrid(children: [
            StatCard(
                label: 'Critical (24h)',
                value: '${day.where((r) => r['severity'] == 'critical').length}',
                icon: Icons.gpp_bad_rounded,
                color: AppColors.danger,
                sub: 'Honeypot hits'),
            StatCard(
                label: 'High (24h)',
                value: '${day.where((r) => r['severity'] == 'high').length}',
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                sub: 'Lockouts, identity reuse'),
            StatCard(
                label: 'Rate limited (24h)',
                value: '${day.where((r) => r['kind'] == 'rate_limited').length}',
                icon: Icons.speed_rounded),
            StatCard(label: 'Events loaded', value: '${_rows.length}', icon: Icons.shield_rounded),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            for (final f in const ['all', 'critical', 'high', 'medium', 'low'])
              ChoiceChip(
                label: Text(f[0].toUpperCase() + f.substring(1)),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ]),
          const SizedBox(height: 12),
          ResponsiveTable(
            columns: const ['When', 'Severity', 'Event', 'User', 'IP', 'Details', ''],
            empty: 'No security events. All quiet.',
            rows: shown
                .map((e) => [
                      Text(dt(e['created_at'])),
                      StatusPill('${e['severity']}', color: _sevColor('${e['severity']}')),
                      Text(_label('${e['kind']}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${e['email'] ?? (e['user_id'] == null ? 'Anonymous' : e['user_id'])}',
                          overflow: TextOverflow.ellipsis),
                      Text('${e['ip'] ?? ''}'),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(e['details'] == null ? '' : jsonEncode(e['details']),
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      ),
                      if ('${e['kind']}'.startsWith('honeypot:') && e['user_id'] != null)
                        TextButton(onPressed: () => _unfreeze(e), child: const Text('Restore'))
                      else
                        const SizedBox.shrink(),
                    ])
                .toList(),
          ),
        ],
      ],
    );
  }
}
