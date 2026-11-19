import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/nova_widgets.dart';
import 'admin_common.dart';

/// API keys and environment. Values are write-only: the server returns only
/// a short mask, and keys are stored encrypted in Supabase Vault.
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});
  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _serverDefaults = {};
  Map<String, dynamic> _config = {};
  final Map<String, (bool, String)> _tests = {};
  final Set<String> _testing = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait<dynamic>([
        arpc('admin_integrations'),
        aops('config_status'),
        arpc('public_config'),
      ]);
      _rows = List<Map<String, dynamic>>.from(r[0] as List);
      _serverDefaults = Map<String, dynamic>.from((r[1] as Map)['server_defaults'] ?? {});
      _config = Map<String, dynamic>.from(r[2] as Map);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final value = await askText(context,
        title: '${r['provider']} · ${r['label']}',
        hint: r['description'],
        obscure: r['is_secret'] == true,
        okLabel: 'Save securely');
    if (value == null || value.trim().isEmpty) return;
    try {
      await arpc('admin_set_secret', {'_name': r['name'], '_value': value.trim()});
      if (mounted) toast(context, '${r['label']} saved. Live within 30 seconds.');
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _clear(Map<String, dynamic> r) async {
    if (!await confirm(context, 'Remove ${r['label']}?',
        'NOVA will fall back to the deployment default for ${r['provider']}, if one exists.',
        ok: 'Remove', danger: true)) {
      return;
    }
    try {
      await arpc('admin_clear_secret', {'_name': r['name']});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _test(String provider) async {
    setState(() => _testing.add(provider));
    try {
      final r = await aops('test_integration', {'provider': provider});
      _tests[provider] = (r['ok'] == true, '${r['message']}');
    } catch (e) {
      _tests[provider] = (false, '$e');
    } finally {
      if (mounted) setState(() => _testing.remove(provider));
    }
  }

  Future<void> _setEnv(String env) async {
    String confirmText = '';
    if (env == 'live') {
      final t = await askText(context,
          title: 'Switch NOVA to LIVE?',
          hint: 'Type GO LIVE to confirm. Make sure every provider has LIVE keys first.',
          okLabel: 'Switch to live');
      if (t == null) return;
      confirmText = t.trim();
    } else if (!await confirm(context, 'Switch to sandbox?', 'Test top-ups, faucets and simulations turn back on.')) {
      return;
    }
    try {
      await arpc('admin_set_environment', {'_env': env, '_confirm': confirmText});
      if (mounted) toast(context, 'Environment set to ${env.toUpperCase()}');
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final env = _config['environment'] ?? 'sandbox';
    final live = env == 'live';
    final providers = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      providers.putIfAbsent(r['provider'], () => []).add(r);
    }

    return AdminPage(
      title: 'Integrations',
      onRefresh: _load,
      children: [
        NovaCard(
          child: Row(children: [
            Icon(Icons.shield_rounded, color: scheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Keys are encrypted in Supabase Vault and are write-only. Nobody (including admins) can read a saved key '
                'back; only a short mask is shown. Changes apply to the backend within 30 seconds, no code changes needed.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        NovaCard(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: live ? AppColors.danger : AppColors.warning),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Environment: ${env.toString().toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(live ? 'Real money and real KYC checks' : 'Test keys, test money, simulations on',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ]),
              ]),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'sandbox', label: Text('Sandbox'), icon: Icon(Icons.science_outlined)),
                  ButtonSegment(value: 'live', label: Text('Live'), icon: Icon(Icons.bolt_rounded)),
                ],
                selected: {env},
                onSelectionChanged: (s) => _setEnv(s.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else
          for (final entry in providers.entries) ...[
            NovaCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (entry.key != 'NOVA Custody' && entry.key != 'Reown (WalletConnect)')
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_tests[entry.key] != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: StatusPill(_tests[entry.key]!.$2,
                                color: _tests[entry.key]!.$1 ? AppColors.success : AppColors.danger),
                          ),
                        OutlinedButton.icon(
                          onPressed: _testing.contains(entry.key) ? null : () => _test(entry.key),
                          icon: _testing.contains(entry.key)
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_tethering_rounded, size: 18),
                          label: const Text('Test connection'),
                        ),
                      ]),
                  ],
                ),
                const SizedBox(height: 8),
                for (final r in entry.value) _KeyRow(
                  row: r,
                  serverDefault: _serverDefaults[r['name']] == true,
                  onEdit: () => _edit(r),
                  onClear: () => _clear(r),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.row, required this.serverDefault, required this.onEdit, required this.onClear});
  final Map<String, dynamic> row;
  final bool serverDefault;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inVault = row['in_vault'] == true;
    final editable = row['editable'] == true;
    final status = inVault
        ? ('Saved in Vault', AppColors.success)
        : serverDefault
            ? ('Using server default', AppColors.warning)
            : ('Not set', scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(row['label'], style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                StatusPill(status.$1, color: status.$2),
              ]),
              const SizedBox(height: 2),
              Text(row['description'] ?? '', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              if (row['masked'] != null) ...[
                const SizedBox(height: 4),
                SelectableText(row['masked'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ]),
          ),
          if (editable)
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (inVault) IconButton(tooltip: 'Remove', onPressed: onClear, icon: const Icon(Icons.delete_outline_rounded)),
              FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: Icon(inVault ? Icons.sync_rounded : Icons.add_rounded, size: 18),
                label: Text(inVault ? 'Replace' : 'Set'),
              ),
            ])
          else
            const StatusPill('Locked'),
        ],
      ),
    );
  }
}
