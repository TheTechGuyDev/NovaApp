import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/data/models.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/nova_widgets.dart';
import 'admin_common.dart';

// ============================================================ OVERVIEW
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await arpc('admin_overview');
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _switch(String key, bool on) async {
    final label = key == 'withdrawals_paused' ? 'withdrawals' : 'trading';
    if (!await confirm(context, on ? 'Pause $label?' : 'Resume $label?',
        on ? 'All customers will be blocked from $label immediately.' : 'Customers can use $label again.',
        ok: on ? 'Pause' : 'Resume', danger: on)) {
      return;
    }
    try {
      await arpc('admin_set_switch', {'_key': key, '_on': on});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    }
    final kyc = Map<String, dynamic>.from(d['kyc'] ?? {});
    final fees = Map<String, dynamic>.from(d['fees'] ?? {});
    final daily = List<Map<String, dynamic>>.from(d['daily'] ?? []);
    final wPaused = d['withdrawals_paused'] == true;
    final tPaused = d['trading_paused'] == true;
    final scheme = Theme.of(context).colorScheme;

    return AdminPage(
      title: 'Overview',
      onRefresh: _load,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          StatusPill('ENV: ${(d['environment'] ?? 'sandbox').toString().toUpperCase()}',
              color: d['environment'] == 'live' ? AppColors.danger : AppColors.warning),
          StatusPill(asDouble(d['recon_issues']) == 0 ? 'Ledger reconciled' : '${d['recon_issues']} reconciliation issues',
              color: asDouble(d['recon_issues']) == 0 ? AppColors.success : AppColors.danger),
          StatusPill('Ledger net ${asDouble(d['ledger_total']).toStringAsFixed(2)}',
              color: asDouble(d['ledger_total']) == 0 ? AppColors.success : AppColors.danger),
        ]),
        const SizedBox(height: 16),
        StatGrid(children: [
          StatCard(label: 'Customers', value: '${d['users']}', icon: Icons.people_alt_rounded, sub: '+${d['users_today']} today'),
          StatCard(label: 'Naira balances', value: ngn(d['ngn_balances']), icon: Icons.account_balance_wallet_rounded),
          StatCard(label: 'Crypto held (₦)', value: ngn(d['crypto_aum_ngn']), icon: Icons.currency_bitcoin_rounded),
          StatCard(label: 'Savings', value: ngn(d['savings']), icon: Icons.savings_rounded),
          StatCard(label: 'Transactions today', value: '${d['txns_today']}', icon: Icons.receipt_long_rounded),
          StatCard(label: 'Outflow today', value: ngn(d['volume_today_ngn']), icon: Icons.north_east_rounded),
          StatCard(label: 'Fees earned (₦)', value: ngn(fees['NGN'] ?? 0), icon: Icons.paid_rounded,
              sub: fees.entries.where((e) => e.key != 'NGN').map((e) => '${formatCrypto(asDouble(e.value))} ${e.key}').join(' · ')),
          StatCard(label: 'Pending / processing', value: '${d['pending']}', icon: Icons.hourglass_top_rounded,
              color: asDouble(d['pending']) > 0 ? AppColors.warning : null),
          StatCard(label: 'Open limit orders', value: '${d['open_orders']}', icon: Icons.candlestick_chart_rounded),
          StatCard(label: 'Active cards', value: '${d['active_cards']}', icon: Icons.credit_card_rounded),
          StatCard(label: 'Restricted accounts', value: '${d['frozen']}', icon: Icons.block_rounded),
          StatCard(
            label: 'KYC levels',
            value: 'L0 ${kyc['0'] ?? 0} · L1 ${kyc['1'] ?? 0} · L2 ${kyc['2'] ?? 0}',
            icon: Icons.verified_user_rounded,
          ),
        ]),
        const SizedBox(height: 20),
        NovaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Emergency controls', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause all withdrawals'),
              subtitle: const Text('Bank transfers and on-chain crypto withdrawals'),
              value: wPaused,
              activeThumbColor: AppColors.danger,
              onChanged: (v) => _switch('withdrawals_paused', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause trading'),
              subtitle: const Text('Instant swaps and new limit orders'),
              value: tPaused,
              activeThumbColor: AppColors.danger,
              onChanged: (v) => _switch('trading_paused', v),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        NovaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Last 14 days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Row(children: [
              _legend(scheme.primary, 'Transactions'),
              const SizedBox(width: 14),
              _legend(AppColors.warning, 'Sign-ups'),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= daily.length || i % 2 == 1) return const SizedBox();
                        return Text((daily[i]['day'] as String).substring(8), style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < daily.length; i++)
                    BarChartGroupData(x: i, barsSpace: 2, barRods: [
                      BarChartRodData(toY: asDouble(daily[i]['txns']), color: scheme.primary, width: 6),
                      BarChartRodData(toY: asDouble(daily[i]['signups']), color: AppColors.warning, width: 6),
                    ]),
                ],
              )),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

// =============================================================== USERS
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await arpc('admin_users', {'_search': _q.text.trim(), '_limit': 100}) as List);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Users',
      onRefresh: _load,
      children: [
        TextField(
          controller: _q,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            hintText: 'Search name, @username, email or phone',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else
          ResponsiveTable(
            columns: const ['Name', 'Username', 'Email', 'KYC', 'Status', 'Naira', 'Joined'],
            rows: _rows
                .map((u) => [
                      Text(u['full_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(u['username'] == null ? '-' : '@${u['username']}'),
                      Text(u['email'] ?? '-'),
                      Text('L${u['kyc_level']}'),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        StatusPill(u['status']),
                        if ((u['roles'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(width: 6),
                          const StatusPill('staff', color: AppColors.primary),
                        ],
                      ]),
                      Text(ngn(u['ngn_balance'], decimals: 2)),
                      Text(dt(u['created_at'])),
                    ])
                .toList(),
            onTap: (i) async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserDetailPage(id: _rows[i]['id'])));
              _load();
            },
          ),
      ],
    );
  }
}

class UserDetailPage extends StatefulWidget {
  const UserDetailPage({super.key, required this.id});
  final String id;
  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  Map<String, dynamic>? _d;

  static const _staffRoles = [
    'super_admin', 'banking_ops', 'crypto_ops', 'exchange_ops', 'compliance',
    'risk', 'treasury', 'support', 'finance', 'tech',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await arpc('admin_user_detail', {'_id': widget.id});
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _status(String status) async {
    final reason = await askText(context, title: status == 'active' ? 'Restore account' : 'Freeze account', hint: 'Reason (saved in the audit log)');
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await arpc('admin_set_user_status', {'_id': widget.id, '_status': status, '_reason': reason});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _kyc() async {
    final lvl = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set KYC level'),
        children: [for (var i = 0; i <= 3; i++) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text('Level $i'))],
      ),
    );
    if (lvl == null || !mounted) return;
    final reason = await askText(context, title: 'Reason for KYC change', hint: 'e.g. Manual document review');
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await arpc('admin_set_kyc', {'_id': widget.id, '_level': lvl, '_reason': reason});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _role(String role, bool grant) async {
    try {
      await arpc('admin_set_role', {'_id': widget.id, '_role': role, '_grant': grant});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final scheme = Theme.of(context).colorScheme;
    if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = Map<String, dynamic>.from(d['profile'] ?? {});
    final roles = List<String>.from(d['roles'] ?? []);
    final wallets = List<Map<String, dynamic>>.from(d['wallets'] ?? []);
    final txns = List<Map<String, dynamic>>.from(d['transactions'] ?? []);
    final kyc = List<Map<String, dynamic>>.from(d['kyc'] ?? []);
    final active = p['status'] == 'active';

    return Scaffold(
      appBar: AppBar(title: Text(p['full_name'] ?? 'User'), centerTitle: false),
      body: AdminPage(
        title: '@${p['username'] ?? '-'}',
        onRefresh: _load,
        actions: [
          OutlinedButton.icon(onPressed: _kyc, icon: const Icon(Icons.verified_user_outlined, size: 18), label: const Text('KYC level')),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: active ? AppColors.danger : AppColors.success,
            ),
            onPressed: () => _status(active ? 'frozen' : 'active'),
            icon: Icon(active ? Icons.ac_unit_rounded : Icons.lock_open_rounded, size: 18),
            label: Text(active ? 'Freeze account' : 'Restore account'),
          ),
        ],
        children: [
          StatGrid(children: [
            StatCard(label: 'Status', value: '${p['status']}'.toUpperCase(), color: active ? AppColors.success : AppColors.danger),
            StatCard(label: 'KYC level', value: 'Level ${p['kyc_level']}'),
            StatCard(label: 'Savings', value: ngn(d['savings'], decimals: 2)),
            StatCard(label: 'Cards', value: '${d['cards']}'),
          ]),
          const SizedBox(height: 16),
          NovaCard(
            child: Column(children: [
              DetailRowA('Email', p['email']),
              DetailRowA('Phone', p['phone']),
              DetailRowA('User ID', p['id'], copy: true),
              DetailRowA('Referral code', p['referral_code']),
              DetailRowA('Joined', dt(p['created_at'])),
              if (d['virtual_account'] != null)
                DetailRowA('Account number', '${d['virtual_account']['account_number']} · ${d['virtual_account']['bank_name']}'),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('Wallets', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Asset', 'Available', 'In orders', 'Status'],
            rows: wallets
                .map((w) => [
                      Text(w['asset'], style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(w['asset'] == 'NGN' ? ngn(w['available'], decimals: 2) : formatCrypto(asDouble(w['available']))),
                      Text(formatCrypto(asDouble(w['locked']))),
                      StatusPill(w['status']),
                    ])
                .toList(),
          ),
          const SizedBox(height: 16),
          Text('Staff roles', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('Only super admins can change roles.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _staffRoles
                .map((r) => FilterChip(
                      label: Text(r.replaceAll('_', ' ')),
                      selected: roles.contains(r),
                      onSelected: (v) => _role(r, v),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('KYC checks', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Check', 'Reference', 'Status', 'Name match', 'Date'],
            empty: 'No KYC checks yet',
            rows: kyc
                .map((k) => [
                      Text('${k['check_type']}'.toUpperCase()),
                      Text('${k['reference'] ?? '-'}'),
                      StatusPill(k['status']),
                      Text(k['result']?['name_match'] == true ? 'Yes' : 'No'),
                      Text(dt(k['created_at'])),
                    ])
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Recent transactions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          _TxnTable(rows: txns),
        ],
      ),
    );
  }
}

class DetailRowA extends StatelessWidget {
  const DetailRowA(this.label, this.value, {super.key, this.copy = false});
  final String label;
  final dynamic value;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
        Expanded(child: SelectableText('${value ?? '-'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        if (copy)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () => Clipboard.setData(ClipboardData(text: '$value')),
          ),
      ]),
    );
  }
}

// ======================================================== TRANSACTIONS
class _TxnTable extends StatelessWidget {
  const _TxnTable({required this.rows, this.showUser = false});
  final List<Map<String, dynamic>> rows;
  final bool showUser;

  @override
  Widget build(BuildContext context) {
    return ResponsiveTable(
      columns: ['Date', if (showUser) 'User', 'Type', 'Title', 'Amount', 'Status', 'Reference'],
      empty: 'No transactions',
      rows: rows.map((t) {
        final a = asDouble(t['amount']);
        final asset = t['asset_code'] as String;
        return [
          Text(dt(t['created_at'])),
          if (showUser) Text(t['username'] == null ? '-' : '@${t['username']}'),
          Text('${t['type']}'.replaceAll('_', ' ')),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text('${t['title'] ?? '-'}', overflow: TextOverflow.ellipsis),
          ),
          Text(
            asset == 'NGN' ? formatMoney(a, symbol: '₦') : '${formatCrypto(a)} $asset',
            style: TextStyle(color: a >= 0 ? AppColors.success : null, fontWeight: FontWeight.w600),
          ),
          StatusPill('${t['status']}'),
          SelectableText('${t['reference']}', style: const TextStyle(fontSize: 12)),
        ];
      }).toList(),
    );
  }
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _q = TextEditingController();
  String? _type;
  String? _status;
  String? _asset;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  static const _types = [
    'deposit', 'withdrawal', 'transfer_in', 'transfer_out', 'bill_payment', 'conversion', 'trade',
    'savings_deposit', 'savings_withdrawal', 'interest', 'card_payment', 'card_funding', 'reversal',
  ];
  static const _statuses = ['pending', 'processing', 'completed', 'failed', 'reversed', 'cancelled'];
  static const _assets = ['NGN', 'USDT', 'BTC', 'ETH', 'USDC', 'SOL', 'BNB'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await arpc('admin_transactions', {
        '_type': _type,
        '_status': _status,
        '_asset': _asset,
        '_search': _q.text.trim(),
        '_limit': 200,
      }) as List);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _drop(String hint, String? value, List<String> items, ValueChanged<String?> on) => SizedBox(
        width: 170,
        child: DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: hint, isDense: true),
          items: [
            const DropdownMenuItem(value: null, child: Text('All')),
            ...items.map((e) => DropdownMenuItem(value: e, child: Text(e.replaceAll('_', ' ')))),
          ],
          onChanged: (v) {
            on(v);
            _load();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Transactions',
      onRefresh: _load,
      children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _q,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(hintText: 'Reference, title, @user or tx hash', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          _drop('Type', _type, _types, (v) => _type = v),
          _drop('Status', _status, _statuses, (v) => _status = v),
          _drop('Asset', _asset, _assets, (v) => _asset = v),
        ]),
        const SizedBox(height: 14),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else
          _TxnTable(rows: _rows, showUser: true),
      ],
    );
  }
}

// ========================================================== CRYPTO OPS
class CryptoOpsPage extends StatefulWidget {
  const CryptoOpsPage({super.key});
  @override
  State<CryptoOpsPage> createState() => _CryptoOpsPageState();
}

class _CryptoOpsPageState extends State<CryptoOpsPage> {
  List<Map<String, dynamic>> _hot = [];
  List<Map<String, dynamic>> _nets = [];
  List<Map<String, dynamic>> _moves = [];
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
        aops('hot_wallets'),
        adb.from('networks').select().order('asset_code').then((v) => v),
        arpc('admin_transactions', {'_type': 'withdrawal', '_limit': 30}),
        arpc('admin_transactions', {'_type': 'deposit', '_asset': null, '_limit': 60}),
      ]);
      _hot = List<Map<String, dynamic>>.from((r[0] as Map)['wallets'] ?? []);
      _nets = List<Map<String, dynamic>>.from(r[1] as List);
      _moves = [
        ...List<Map<String, dynamic>>.from(r[2] as List),
        ...List<Map<String, dynamic>>.from(r[3] as List).where((t) => t['asset_code'] != 'NGN'),
      ]..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> n, {bool? dep, bool? wd}) async {
    try {
      await arpc('admin_update_network', {'_id': n['id'], '_deposits': dep, '_withdrawals': wd});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _fee(Map<String, dynamic> n) async {
    final v = await askText(context, title: '${n['id']} withdrawal fee', initial: '${asDouble(n['withdrawal_fee'])}', hint: 'In ${n['asset_code']}');
    final f = double.tryParse(v ?? '');
    if (f == null) return;
    try {
      await arpc('admin_update_network', {'_id': n['id'], '_deposits': null, '_withdrawals': null, '_fee': f});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Crypto Operations',
      onRefresh: _load,
      children: [
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else ...[
          const Text('Hot wallets (withdrawals are paid from these)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Chain', 'Address', 'On-chain balance', 'User addresses'],
            rows: _hot
                .map((h) => [
                      Text('${h['chain']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      SelectableText('${h['address']}', style: const TextStyle(fontSize: 12)),
                      Text(h['balance'] == null ? 'unavailable' : '${formatCrypto(asDouble(h['balance']))} ${h['symbol']}',
                          style: TextStyle(color: asDouble(h['balance']) == 0 ? AppColors.warning : null, fontWeight: FontWeight.w600)),
                      Text('${h['addresses_issued']}'),
                    ])
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Networks', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Route', 'Deposits', 'Withdrawals', 'Fee', 'Min', 'Confirmations'],
            rows: _nets
                .map((n) => [
                      Text('${n['asset_code']} · ${n['network']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Switch(value: n['deposits_enabled'] == true, onChanged: (v) => _toggle(n, dep: v)),
                      Switch(value: n['withdrawals_enabled'] == true, onChanged: (v) => _toggle(n, wd: v)),
                      InkWell(onTap: () => _fee(n), child: Text('${formatCrypto(asDouble(n['withdrawal_fee']))} ✎')),
                      Text(formatCrypto(asDouble(n['min_withdrawal']))),
                      Text('${n['confirmations_required']}'),
                    ])
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Recent crypto deposits & withdrawals', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          _TxnTable(rows: _moves.take(50).toList(), showUser: true),
        ],
      ],
    );
  }
}

// ============================================================ EXCHANGE
class ExchangeAdminPage extends StatefulWidget {
  const ExchangeAdminPage({super.key});
  @override
  State<ExchangeAdminPage> createState() => _ExchangeAdminPageState();
}

class _ExchangeAdminPageState extends State<ExchangeAdminPage> {
  List<Map<String, dynamic>> _pairs = [];
  List<Map<String, dynamic>> _rates = [];
  List<Map<String, dynamic>> _orders = [];
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
        adb.from('trading_pairs').select().order('symbol').then((v) => v),
        adb.from('rates').select().order('asset_code').then((v) => v),
        adb.from('orders').select().order('created_at', ascending: false).limit(50).then((v) => v),
      ]);
      _pairs = List<Map<String, dynamic>>.from(r[0] as List);
      _rates = List<Map<String, dynamic>>.from(r[1] as List);
      _orders = List<Map<String, dynamic>>.from(r[2] as List);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(Map<String, dynamic> p, {bool? enabled, double? fee}) async {
    try {
      await arpc('admin_update_pair', {'_symbol': p['symbol'], '_enabled': enabled, '_fee': fee});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Exchange',
      onRefresh: _load,
      children: [
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else ...[
          const Text('Live rates (refreshed every minute)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Asset', 'NGN price', 'USD price', '24h', 'Updated'],
            rows: _rates
                .map((r) => [
                      Text('${r['asset_code']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(ngn(r['ngn_price'], decimals: 2)),
                      Text(formatMoney(asDouble(r['usd_price']), symbol: '\$', decimals: asDouble(r['usd_price']) < 1 ? 6 : 2)),
                      ChangeChip(asDouble(r['change_24h'])),
                      Text(dt(r['updated_at'])),
                    ])
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Trading pairs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Pair', 'Enabled', 'Fee %', ''],
            rows: _pairs
                .map((p) => [
                      Text('${p['symbol']}'.replaceAll('_', ' / '), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Switch(value: p['enabled'] == true, onChanged: (v) => _update(p, enabled: v)),
                      Text('${asDouble(p['fee_pct']).toStringAsFixed(2)}%'),
                      TextButton(
                        onPressed: () async {
                          final v = await askText(context, title: '${p['symbol']} fee %', initial: '${asDouble(p['fee_pct'])}');
                          final f = double.tryParse(v ?? '');
                          if (f != null) _update(p, fee: f);
                        },
                        child: const Text('Edit fee'),
                      ),
                    ])
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Recent limit orders', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Date', 'Pair', 'Side', 'Price', 'Amount', 'Status'],
            empty: 'No orders yet',
            rows: _orders
                .map((o) => [
                      Text(dt(o['created_at'])),
                      Text('${o['pair']}'.replaceAll('_', '/')),
                      StatusPill('${o['side']}', color: o['side'] == 'buy' ? AppColors.success : AppColors.danger),
                      Text(formatCrypto(asDouble(o['price']))),
                      Text(formatCrypto(asDouble(o['amount']))),
                      StatusPill('${o['status']}'),
                    ])
                .toList(),
          ),
        ],
      ],
    );
  }
}

// ============================================================= FINANCE
class FinancePage extends StatefulWidget {
  const FinancePage({super.key});
  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await arpc('admin_finance');
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  String _amt(String asset, dynamic v) => asset == 'NGN' ? ngn(v, decimals: 2) : '${formatCrypto(asDouble(v))} $asset';

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final sys = List<Map<String, dynamic>>.from(d['system_accounts'] ?? []);
    final cust = List<Map<String, dynamic>>.from(d['customer_balances'] ?? []);
    final ledger = List<Map<String, dynamic>>.from(d['ledger_by_asset'] ?? []);
    final recon = List<Map<String, dynamic>>.from(d['recon_issues'] ?? []);
    final sv = Map<String, dynamic>.from(d['savings_pool_vs_plans'] ?? {});
    final svOk = asDouble(sv['pool']) == asDouble(sv['plans']);

    return AdminPage(
      title: 'Finance & Reconciliation',
      onRefresh: _load,
      children: [
        StatGrid(children: [
          StatCard(
            label: 'Wallet reconciliation',
            value: recon.isEmpty ? 'All balanced' : '${recon.length} issues',
            color: recon.isEmpty ? AppColors.success : AppColors.danger,
            icon: Icons.fact_check_rounded,
          ),
          StatCard(
            label: 'Ledger (must be 0)',
            value: ledger.every((l) => asDouble(l['net']) == 0) ? 'Balanced' : 'Imbalanced',
            color: ledger.every((l) => asDouble(l['net']) == 0) ? AppColors.success : AppColors.danger,
            icon: Icons.balance_rounded,
          ),
          StatCard(
            label: 'Savings pool vs plans',
            value: svOk ? 'Matches' : 'Mismatch',
            sub: '${ngn(sv['pool'], decimals: 2)} / ${ngn(sv['plans'], decimals: 2)}',
            color: svOk ? AppColors.success : AppColors.danger,
            icon: Icons.savings_rounded,
          ),
          StatCard(label: 'Journals (24h)', value: '${d['journals_24h']}', icon: Icons.menu_book_rounded),
        ]),
        const SizedBox(height: 20),
        const Text('Customer balances (NOVA owes customers)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        ResponsiveTable(
          columns: const ['Asset', 'Total'],
          rows: cust.map((c) => [Text('${c['asset']}', style: const TextStyle(fontWeight: FontWeight.w600)), Text(_amt(c['asset'], c['total']))]).toList(),
        ),
        const SizedBox(height: 20),
        const Text('System accounts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Negative = NOVA has paid out more than received in that account (e.g. liquidity provided).',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        ResponsiveTable(
          columns: const ['Account', 'Asset', 'Balance'],
          rows: sys
              .map((s) => [
                    Text('${s['id']}'.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${s['asset']}'),
                    Text(_amt(s['asset'], s['balance']),
                        style: TextStyle(color: asDouble(s['balance']) < 0 ? AppColors.danger : AppColors.success)),
                  ])
              .toList(),
        ),
        if (recon.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Reconciliation issues', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.danger)),
          const SizedBox(height: 8),
          ResponsiveTable(
            columns: const ['Wallet', 'Asset', 'Balance', 'Ledger', 'Difference'],
            rows: recon
                .map((r) => [
                      SelectableText('${r['wallet_id']}', style: const TextStyle(fontSize: 11)),
                      Text('${r['asset_code']}'),
                      Text(formatCrypto(asDouble(r['available']))),
                      Text(formatCrypto(asDouble(r['ledger_total']))),
                      Text(formatCrypto(asDouble(r['difference'])), style: const TextStyle(color: AppColors.danger)),
                    ])
                .toList(),
          ),
        ],
      ],
    );
  }
}

// ============================================================ SETTINGS
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _s = {};
  bool _loading = true;

  static const _editable = {
    'fees': 'Transfer & bill fees',
    'savings_rates': 'Savings interest rates (% per year)',
    'kyc_tiers': 'KYC tiers and daily limits',
    'quote_ttl_seconds': 'Exchange quote lifetime (seconds)',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await adb.from('app_settings').select().inFilter('key', _editable.keys.toList());
      _s = {for (final row in r as List) row['key'] as String: row['value']};
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(String key) async {
    final pretty = const JsonEncoder.withIndent('  ').convert(_s[key]);
    final c = TextEditingController(text: pretty);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_editable[key]!),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: c,
            maxLines: 16,
            minLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v == null) return;
    try {
      final parsed = jsonDecode(v);
      await arpc('admin_set_setting', {'_key': key, '_value': parsed});
      if (mounted) toast(context, 'Saved');
      _load();
    } on FormatException {
      if (mounted) toast(context, 'That is not valid JSON', error: true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminPage(
      title: 'Platform Settings',
      onRefresh: _load,
      children: [
        Text('Changes apply immediately and are recorded in the audit log.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 14),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          for (final e in _editable.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NovaCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700))),
                    FilledButton.tonalIcon(
                      onPressed: () => _edit(e.key),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(_s[e.key]),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
      ],
    );
  }
}

// =============================================================== AUDIT
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await arpc('admin_audit', {'_limit': 300}) as List);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Audit Log',
      onRefresh: _load,
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          ResponsiveTable(
            columns: const ['When', 'Who', 'Action', 'Target', 'Details'],
            empty: 'No activity yet',
            rows: _rows
                .map((a) => [
                      Text(dt(a['created_at'])),
                      Text('${a['actor']}'),
                      Text('${a['action']}'.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${a['entity'] ?? ''} ${a['entity_id'] ?? ''}'.trim(), overflow: TextOverflow.ellipsis),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(a['details'] == null ? '' : jsonEncode(a['details']),
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      ),
                    ])
                .toList(),
          ),
      ],
    );
  }
}
