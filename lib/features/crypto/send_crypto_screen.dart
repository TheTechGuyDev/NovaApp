import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';

class SendCryptoScreen extends StatelessWidget {
  const SendCryptoScreen({super.key, required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Send $symbol'),
          bottom: const TabBar(tabs: [Tab(text: 'NOVA User'), Tab(text: 'External Wallet')]),
        ),
        body: TabBarView(children: [_ToNova(symbol: symbol), _ToAddress(symbol: symbol)]),
      ),
    );
  }
}

class _CryptoAmount extends StatelessWidget {
  const _CryptoAmount({required this.controller, required this.symbol, this.onChanged, this.onMax});
  final TextEditingController controller;
  final String symbol;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onMax;

  @override
  Widget build(BuildContext context) {
    final h = context.watch<NovaStore>().holding(symbol)!;
    final v = double.tryParse(controller.text) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'))],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: symbol,
            helperText: (v > 0 ? '≈ ${formatMoney(v * h.priceNgn, symbol: '₦')}' : null),
            prefixIcon: onMax == null
                ? null
                : TextButton(onPressed: onMax, child: const Text('MAX')),
          ),
        ),
        const SizedBox(height: 6),
        Text('Available: ${h.balanceLabel}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }
}

// ------------------------------------------------------------ NOVA user
class _ToNova extends StatefulWidget {
  const _ToNova({required this.symbol});
  final String symbol;
  @override
  State<_ToNova> createState() => _ToNovaState();
}

class _ToNovaState extends State<_ToNova> {
  final _user = TextEditingController();
  final _amt = TextEditingController();
  Timer? _debounce;
  Map<String, String>? _rcpt;
  bool _busy = false;
  final _key = newIdempotencyKey();

  void _lookup(String v) {
    _debounce?.cancel();
    setState(() => _rcpt = null);
    final u = v.trim().replaceFirst('@', '');
    if (u.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final r = await context.read<NovaStore>().lookupUser(u);
      if (mounted) setState(() => _rcpt = r);
    });
  }

  Future<void> _send() async {
    final store = context.read<NovaStore>();
    final amount = double.parse(_amt.text);
    final pin = await askPin(context,
        title: 'Confirm transfer', subtitle: 'Send ${formatCrypto(amount)} ${widget.symbol} to ${_rcpt!['full_name']}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await store.crypto('send_internal', {
        'asset': widget.symbol,
        'username': _rcpt!['username'],
        'amount': amount,
        'pin': pin,
        'idempotency_key': _key,
      });
      await store.refreshMoney();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          title: 'Sent to ${_rcpt!['full_name']}',
          amount: '${formatCrypto(amount)} ${widget.symbol}',
          rows: [('Recipient', '@${_rcpt!['username']}'), ('Fee', 'Free · instant'), ('Reference', '${r['reference']}')],
        ),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<NovaStore>().profile?.username;
    final v = double.tryParse(_amt.text) ?? 0;
    final ok = _rcpt != null && _rcpt!['username'] != me && v > 0 && !_busy;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _user,
          onChanged: _lookup,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'NOVA username', prefixText: '@ '),
        ),
        const SizedBox(height: 10),
        if (_rcpt != null)
          NovaCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.verified_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(_rcpt!['username'] == me ? "That's you" : _rcpt!['full_name']!,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        const SizedBox(height: 18),
        _CryptoAmount(controller: _amt, symbol: widget.symbol, onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: ok ? _send : null,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send · Free & instant'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- external wallet
class _ToAddress extends StatefulWidget {
  const _ToAddress({required this.symbol});
  final String symbol;
  @override
  State<_ToAddress> createState() => _ToAddressState();
}

class _ToAddressState extends State<_ToAddress> {
  final _addr = TextEditingController();
  final _amt = TextEditingController();
  String? _networkId;
  bool _busy = false;
  bool _loading = true;
  final _key = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<NovaStore>();
    try {
      if (store.depositAddresses.isEmpty) await store.loadDepositAddresses();
      final nets = _nets(store).where((n) => n['withdrawals_enabled'] == true).toList();
      if (nets.isNotEmpty) _networkId = nets.first['network_id'];
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _nets(NovaStore s) =>
      s.depositAddresses.where((a) => a['asset'] == widget.symbol).toList();

  Future<void> _send(Map<String, dynamic> net) async {
    final store = context.read<NovaStore>();
    final amount = double.parse(_amt.text);
    final fee = (net['withdrawal_fee'] as num).toDouble();
    final pin = await askPin(context,
        title: 'Confirm withdrawal',
        subtitle: '${formatCrypto(amount)} ${widget.symbol} on ${net['network']}\n'
            'Network fee ${formatCrypto(fee)} ${widget.symbol}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await store.crypto('withdraw', {
        'network_id': net['network_id'],
        'address': _addr.text.trim(),
        'amount': amount,
        'pin': pin,
        'idempotency_key': _key,
      });
      await store.refreshMoney();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          title: r['internal'] == true ? 'Sent to a NOVA wallet' : 'Withdrawal sent',
          amount: '${formatCrypto(amount)} ${widget.symbol}',
          rows: [
            ('Network', '${net['network']}'),
            ('To', _addr.text.trim()),
            ('Fee', r['internal'] == true ? 'Free (NOVA address)' : '${formatCrypto((r['fee'] as num).toDouble())} ${widget.symbol}'),
            ('Reference', '${r['reference']}'),
            if (r['tx_hash'] != null) ('Tx hash', '${r['tx_hash']}'),
            if (r['simulated'] == true) ('Mode', 'Sandbox simulation (hot wallet unfunded)'),
          ],
        ),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final nets = _nets(store);
    final net = nets.where((n) => n['network_id'] == _networkId).firstOrNull;
    final enabled = nets.where((n) => n['withdrawals_enabled'] == true).toList();
    if (enabled.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('On-chain ${widget.symbol} withdrawals open at mainnet launch. '
              'You can still send ${widget.symbol} to NOVA users instantly.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final fee = (net?['withdrawal_fee'] as num?)?.toDouble() ?? 0;
    final min = (net?['min_withdrawal'] as num?)?.toDouble() ?? 0;
    final v = double.tryParse(_amt.text) ?? 0;
    final bal = store.holding(widget.symbol)!.balance;
    final ok = net != null && _addr.text.trim().length > 20 && v >= min && v + fee <= bal + 1e-12 && !_busy;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Network', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: enabled
              .map((n) => ChoiceChip(
                    label: Text(n['network']),
                    selected: n['network_id'] == _networkId,
                    onSelected: (_) => setState(() => _networkId = n['network_id']),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _addr,
          onChanged: (_) => setState(() {}),
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Recipient ${net?['network'] ?? ''} address',
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) setState(() => _addr.text = d!.text!.trim());
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CryptoAmount(
          controller: _amt,
          symbol: widget.symbol,
          onChanged: (_) => setState(() {}),
          onMax: () => setState(() {
            final m = (bal - fee).clamp(0, double.infinity);
            _amt.text = m.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
          }),
        ),
        const SizedBox(height: 14),
        NovaCard(
          child: Column(children: [
            DetailRow('Network fee', '${formatCrypto(fee)} ${widget.symbol}'),
            DetailRow('Minimum', '${formatCrypto(min)} ${widget.symbol}'),
            DetailRow('Total deducted', '${formatCrypto(v + fee)} ${widget.symbol}'),
          ]),
        ),
        const SizedBox(height: 10),
        const Text('Double-check the address and network. Blockchain transfers cannot be reversed.',
            style: TextStyle(color: AppColors.warning, fontSize: 12)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: ok ? () => _send(net) : null,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue'),
        ),
      ],
    );
  }
}
