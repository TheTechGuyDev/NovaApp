import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';
import 'create_wallet_screen.dart';
import 'self_custody.dart';

class WalletDetailScreen extends StatefulWidget {
  const WalletDetailScreen({super.key, required this.wallet});
  final ScWallet wallet;
  @override
  State<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends State<WalletDetailScreen> {
  late ScChain _chain = scChains.firstWhere((c) => widget.wallet.addressFor(c) != null);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() => context.read<SelfCustodyStore>().refreshBalances(widget.wallet);

  Future<bool> _pinOk(String title) async {
    final pin = await askPin(context, title: title);
    if (pin == null || !mounted) return false;
    try {
      final ok = await context.read<NovaStore>().checkPin(pin);
      if (!ok && mounted) showError(context, 'Incorrect PIN');
      return ok;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    }
  }

  Future<void> _backup() async {
    if (!await _pinOk('Enter PIN to reveal phrase')) return;
    if (!mounted) return;
    final phrase = await context.read<SelfCustodyStore>().revealPhrase(widget.wallet);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Recovery phrase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Anyone with these words controls this wallet.',
                style: TextStyle(color: AppColors.warning, fontSize: 13)),
            const SizedBox(height: 16),
            PhraseGrid(words: phrase.split(' ')),
          ]),
        ),
      ),
    );
  }

  Future<void> _menu(String v) async {
    final sc = context.read<SelfCustodyStore>();
    switch (v) {
      case 'backup':
        await _backup();
      case 'rename':
        final c = TextEditingController(text: widget.wallet.label);
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rename wallet'),
            content: TextField(controller: c, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
            ],
          ),
        );
        if (name != null && name.trim().isNotEmpty) await sc.rename(widget.wallet, name.trim());
      case 'remove':
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove from this device?'),
            content: Text(widget.wallet.watchOnly
                ? 'The connection will be removed. Your wallet app is not affected.'
                : 'Make sure your recovery phrase is backed up. Without it, funds in this wallet are lost.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        );
        if (yes == true && (widget.wallet.watchOnly || await _pinOk('Enter PIN to remove wallet'))) {
          await sc.remove(widget.wallet);
          if (mounted) Navigator.pop(context);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SelfCustodyStore>();
    final w = widget.wallet;
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);
    final address = w.addressFor(_chain)!;
    final bal = sc.balances[w.id]?[_chain.key];
    final chains = scChains.where((c) => w.addressFor(c) != null).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(w.label),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              if (!w.watchOnly) const PopupMenuItem(value: 'backup', child: Text('Back up recovery phrase')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'remove', child: Text('Remove from device')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: chains
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c.name),
                            selected: c.key == _chain.key,
                            onSelected: (_) => setState(() => _chain = c),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_chain.name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: Text(w.watchOnly ? 'CONNECTED' : 'SELF-CUSTODY',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  bal == null ? '... ${_chain.symbol}' : '${formatCrypto(bal)} ${_chain.symbol}',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text('Testnet balance (no real value)', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: w.watchOnly || !_chain.canSend
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SelfSendScreen(wallet: w, chain: _chain, balance: bal ?? 0),
                          )),
                  icon: const Icon(Icons.north_east_rounded),
                  label: const Text('Send'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => launchUrl(Uri.parse(_chain.explorerAddress.replaceAll('{address}', address)),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Explorer'),
                ),
              ),
            ]),
            if (w.watchOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Connected wallets sign in their own app. NOVA shows balances only.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              )
            else if (!_chain.canSend)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Receiving works now. Sending BTC from self-custody comes in a later update.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ),
            const SizedBox(height: 20),
            Text('Receive', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(data: address, size: 170, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            NovaCard(
              onTap: () {
                Clipboard.setData(ClipboardData(text: address));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
              },
              child: Row(children: [
                Expanded(child: SelectableText(address, style: const TextStyle(fontWeight: FontWeight.w500))),
                const SizedBox(width: 8),
                Icon(Icons.copy_rounded, size: 18, color: scheme.primary),
              ]),
            ),
            const SizedBox(height: 10),
            Text(
              _chain.kind == ChainKind.evm
                  ? 'This address works on every EVM network (Ethereum, BNB Chain). Pick the network you send on.'
                  : 'Only send ${_chain.symbol} on ${_chain.name} to this address.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class SelfSendScreen extends StatefulWidget {
  const SelfSendScreen({super.key, required this.wallet, required this.chain, required this.balance});
  final ScWallet wallet;
  final ScChain chain;
  final double balance;
  @override
  State<SelfSendScreen> createState() => _SelfSendScreenState();
}

class _SelfSendScreenState extends State<SelfSendScreen> {
  final _to = TextEditingController();
  final _amt = TextEditingController();
  double? _fee;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<SelfCustodyStore>().estimateFee(widget.chain).then((f) {
      if (mounted) setState(() => _fee = f);
    }).catchError((_) {});
  }

  Future<void> _send() async {
    final c = widget.chain;
    final amount = double.parse(_amt.text);
    final pin = await askPin(context,
        title: 'Approve transaction', subtitle: 'Send ${formatCrypto(amount)} ${c.symbol} on ${c.name}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!await context.read<NovaStore>().checkPin(pin)) throw NovaException('Incorrect PIN');
      if (!mounted) return;
      final hash = await context.read<SelfCustodyStore>().send(widget.wallet, c, _to.text.trim(), amount);
      if (!mounted) return;
      context.read<SelfCustodyStore>().refreshBalances(widget.wallet);
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          title: 'Transaction broadcast',
          amount: '${formatCrypto(amount)} ${c.symbol}',
          highlight: ('Transaction hash', hash),
          rows: [
            ('Network', c.name),
            ('From', widget.wallet.addressFor(c)!),
            ('To', _to.text.trim()),
            ('Signed', 'On this device'),
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
    final c = widget.chain;
    final v = double.tryParse(_amt.text) ?? 0;
    final fee = _fee ?? 0;
    final validTo = SelfCustodyStore.validAddress(c, _to.text.trim());
    // New Solana accounts must receive at least the rent-exempt minimum.
    final minAmt = c.kind == ChainKind.solana ? 0.001 : 0.0;
    final ok = validTo && v > 0 && v >= minAmt && v + fee <= widget.balance && !_busy;
    return Scaffold(
      appBar: AppBar(title: Text('Send ${c.symbol}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _to,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Recipient address (${c.name})',
              errorText: _to.text.trim().isNotEmpty && !validTo ? 'Invalid address' : null,
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) setState(() => _to.text = d!.text!.trim());
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amt,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,9}'))],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Amount',
              suffixText: c.symbol,
              prefixIcon: TextButton(
                onPressed: () => setState(() {
                  final m = (widget.balance - fee * 1.2).clamp(0, double.infinity);
                  _amt.text = m.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
                }),
                child: const Text('MAX'),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Balance: ${formatCrypto(widget.balance)} ${c.symbol}'
              '${c.kind == ChainKind.solana ? ' · minimum 0.001 SOL' : ''}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 14),
          NovaCard(
            child: Column(children: [
              DetailRow('Estimated network fee', _fee == null ? '...' : '${formatCrypto(fee)} ${c.symbol}'),
              DetailRow('Total', '${formatCrypto(v + fee)} ${c.symbol}'),
              const DetailRow('Signing', 'On this device'),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('Blockchain transfers are final. Double-check the address and network.',
              style: TextStyle(color: AppColors.warning, fontSize: 12)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: ok ? _send : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Review & Send'),
          ),
        ],
      ),
    );
  }
}
