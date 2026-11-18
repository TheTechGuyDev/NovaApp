import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../../core/widgets/pin_pad.dart';
import '../money/money_widgets.dart';

const _cardColors = {
  'green': [Color(0xFF1C7A41), Color(0xFF0D2A18)],
  'purple': [Color(0xFF6D28D9), Color(0xFF1E1B4B)],
  'blue': [Color(0xFF1D4ED8), Color(0xFF0C1E4A)],
  'black': [Color(0xFF374151), Color(0xFF050505)],
  'gold': [Color(0xFFB7791F), Color(0xFF3B2A07)],
};

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});
  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final _pager = PageController(viewportFraction: 0.9);
  int _index = 0;
  Map<String, String>? _revealed;

  NovaStore get _store => context.read<NovaStore>();

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      await _store.loadCards();
      if (ok != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _create() async {
    String currency = 'NGN';
    String color = 'green';
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('New virtual card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            for (final c in [
              ('NGN', 'Naira card (Verve)', 'Spends straight from your Naira wallet. Free.'),
              ('USD', 'Dollar card (Visa)', 'Prefund in USD for Netflix, Amazon and global sites. 1% funding fee.'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NovaCard(
                  onTap: () => set(() => currency = c.$1),
                  child: Row(children: [
                    Icon(currency == c.$1 ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(c.$3, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: _cardColors.entries
                  .map((e) => GestureDetector(
                        onTap: () => set(() => color = e.key),
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: e.value),
                            border: Border.all(
                                color: color == e.key ? Theme.of(ctx).colorScheme.primary : Colors.transparent, width: 3),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create card')),
          ]),
        );
      }),
    );
    if (go != true) return;
    await _run(() => _store.rpc('card_create', {'_currency': currency, '_color': color}), ok: 'Card created');
    if (mounted && _store.cards.isNotEmpty) {
      setState(() => _index = _store.cards.length - 1);
      if (_pager.hasClients) _pager.jumpToPage(_index);
    }
  }

  Future<void> _reveal(CardModel c) async {
    if (_revealed?['id'] == c.id) return setState(() => _revealed = null);
    final pin = await askPin(context, title: 'Show card details');
    if (pin == null) return;
    try {
      final r = await _store.rpc('card_reveal', {'_card': c.id, '_pin': pin}) as Map;
      setState(() => _revealed = {'id': c.id, 'pan': r['pan'], 'cvv': r['cvv'], 'expiry': r['expiry']});
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _revealed?['id'] == c.id) setState(() => _revealed = null);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _fund(CardModel c) async {
    final ctrl = TextEditingController();
    final rate = _store.rates['USDT']?.ngn ?? 1500;
    final usd = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, set) {
          final v = double.tryParse(ctrl.text) ?? 0;
          final ngn = v * rate;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Fund dollar card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              onChanged: (_) => set(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ '),
            ),
            const SizedBox(height: 10),
            DetailRow('Rate', '\$1 = ${formatMoney(rate, symbol: '₦')}'),
            DetailRow('You pay', '${formatMoney(ngn, symbol: '₦')} + ${formatMoney(ngn * 0.01, symbol: '₦')} fee'),
            const SizedBox(height: 14),
            FilledButton(onPressed: v >= 1 ? () => Navigator.pop(ctx, v) : null, child: const Text('Fund card')),
          ]);
        }),
      ),
    );
    if (usd == null || !mounted) return;
    final pin = await askPin(context, title: 'Confirm funding', subtitle: 'Add \$${usd.toStringAsFixed(2)} to •••• ${c.last4}');
    if (pin == null) return;
    await _run(() async {
      await _store.rpc('card_fund', {'_card': c.id, '_usd': usd, '_pin': pin, '_key': newIdempotencyKey()});
      await _store.refreshMoney();
    }, ok: 'Card funded');
  }

  Future<void> _testPurchase(CardModel c) async {
    try {
      final r = await _store.rpc('card_simulate_purchase', {'_card': c.id}) as Map;
      await Future.wait([_store.loadCards(), _store.refreshMoney()]);
      if (!mounted) return;
      final amt = r['currency'] == 'USD'
          ? '\$${(r['amount'] as num).toStringAsFixed(2)}'
          : formatMoney((r['amount'] as num).toDouble(), symbol: '₦');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approved: $amt at ${r['merchant']}')));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _limit(CardModel c) async {
    final ctrl = TextEditingController(text: c.dailyLimit.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily spending limit'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(prefixText: c.currency == 'USD' ? '\$ ' : '₦ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) await _run(() => _store.rpc('card_update', {'_card': c.id, '_daily_limit': v}), ok: 'Limit updated');
  }

  Future<void> _setCardPin(CardModel c) async {
    final cardPin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('New card PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Used for card-present payments', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            PinPad(onCompleted: (p) => Navigator.pop(ctx, p)),
          ]),
        ),
      ),
    );
    if (cardPin == null || !mounted) return;
    final pin = await askPin(context, title: 'Enter your NOVA PIN');
    if (pin == null) return;
    await _run(() => _store.rpc('card_set_pin', {'_card': c.id, '_card_pin': cardPin, '_pin': pin}), ok: 'Card PIN set');
  }

  Future<void> _terminate(CardModel c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this card?'),
        content: Text(c.currency == 'USD' && c.balance > 0
            ? 'The remaining \$${c.balance.toStringAsFixed(2)} will be refunded to your Naira wallet.'
            : 'This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final pin = await askPin(context, title: 'Confirm card deletion');
    if (pin == null) return;
    await _run(() async {
      await _store.rpc('card_terminate', {'_card': c.id, '_pin': pin});
      await _store.refreshMoney();
      setState(() => _index = 0);
    }, ok: 'Card deleted');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final scheme = Theme.of(context).colorScheme;
    final cards = store.cards;
    final c = cards.isEmpty ? null : cards[_index.clamp(0, cards.length - 1)];
    final cardTxns = c == null
        ? <TxnItem>[]
        : store.transactions.where((t) => t.metadata['card_id'] == c.id).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: store.loadCards,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const SizedBox(width: 44),
                const Expanded(
                  child: Center(child: Text('Cards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                ),
                RoundIconButton(icon: Icons.add_rounded, onTap: _create),
              ]),
            ),
            const SizedBox(height: 20),
            if (c == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: NovaCard(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  child: Column(children: [
                    Icon(Icons.credit_card_rounded, size: 42, color: scheme.primary),
                    const SizedBox(height: 10),
                    const Text('Get a virtual card in seconds', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text('Naira card for local payments, dollar card for Netflix, Amazon and more.',
                        textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _create, child: const Text('Create card')),
                  ]),
                ),
              )
            else ...[
              SizedBox(
                height: 215,
                child: PageView.builder(
                  controller: _pager,
                  itemCount: cards.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _revealed = null;
                  }),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _CardFace(card: cards[i], revealed: _revealed?['id'] == cards[i].id ? _revealed : null),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  Row(children: [
                    _Action(Icons.visibility_outlined, _revealed?['id'] == c.id ? 'Hide' : 'Details', () => _reveal(c)),
                    _Action(c.frozen ? Icons.lock_open_rounded : Icons.ac_unit_rounded, c.frozen ? 'Unfreeze' : 'Freeze',
                        () => _run(() => _store.rpc('card_update', {'_card': c.id, '_status': c.frozen ? 'active' : 'frozen'}),
                            ok: c.frozen ? 'Card unfrozen' : 'Card frozen')),
                    if (c.currency == 'USD') _Action(Icons.add_card_rounded, 'Fund', () => _fund(c)),
                    _Action(Icons.shopping_bag_outlined, 'Test buy', () => _testPurchase(c)),
                  ]),
                  const SizedBox(height: 14),
                  NovaCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(children: [
                      if (c.currency == 'USD') DetailRow('Card balance', '\$${c.balance.toStringAsFixed(2)}'),
                      if (c.currency == 'NGN')
                        DetailRow('Spends from',
                            'Naira wallet ${formatMoney(store.holding('NGN')?.balance ?? 0, symbol: '₦')}'),
                      InkWell(
                        onTap: () => _limit(c),
                        child: DetailRow(
                            'Daily limit',
                            c.currency == 'USD'
                                ? '\$${c.dailyLimit.toStringAsFixed(0)} ›'
                                : '${formatMoney(c.dailyLimit, symbol: '₦', decimals: 0)} ›'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Online payments', style: TextStyle(fontSize: 14)),
                        value: c.online,
                        onChanged: (v) => _run(() => _store.rpc('card_update', {'_card': c.id, '_online': v})),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('International payments', style: TextStyle(fontSize: 14)),
                        value: c.international,
                        onChanged: (v) => _run(() => _store.rpc('card_update', {'_card': c.id, '_international': v})),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Set card PIN', style: TextStyle(fontSize: 14)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _setCardPin(c),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Delete card', style: TextStyle(fontSize: 14, color: AppColors.danger)),
                        onTap: () => _terminate(c),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Card transactions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                  const SizedBox(height: 10),
                  if (cardTxns.isEmpty)
                    Text('No card payments yet. Tap "Test buy" to simulate one.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
                  else
                    ...cardTxns.map((t) {
                      final usd = t.metadata['usd'];
                      final label = t.type == 'card_funding'
                          ? '+\$${usd ?? ''}'
                          : usd != null
                              ? '-\$${(usd as num).abs().toStringAsFixed(2)}'
                              : t.amountLabel;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NovaCard(
                          onTap: () => showTxnDetails(context, t),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Icon(t.type == 'card_funding' ? Icons.add_card_rounded : Icons.storefront_rounded,
                                color: scheme.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text('${friendlyDate(t.createdAt)} · ${t.metadata['merchant_category'] ?? 'Funding'}',
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                              ]),
                            ),
                            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  Text('Virtual cards are simulated in the sandbox until a card issuer is connected.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: NovaCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, this.revealed});
  final CardModel card;
  final Map<String, String>? revealed;

  @override
  Widget build(BuildContext context) {
    final name = (context.watch<NovaStore>().profile?.fullName ?? '').toUpperCase();
    final colors = _cardColors[card.color] ?? _cardColors['green']!;
    final pan = revealed?['pan'];
    final shown = pan == null
        ? '••••  ••••  ••••  ${card.last4}'
        : '${pan.substring(0, 4)}  ${pan.substring(4, 8)}  ${pan.substring(8, 12)}  ${pan.substring(12)}';

    return Opacity(
      opacity: card.frozen ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(card.currency == 'USD' ? 'USD · \$${card.balance.toStringAsFixed(2)}' : 'NGN',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (card.frozen) const Icon(Icons.ac_unit_rounded, color: Colors.white, size: 16),
            const Spacer(),
            const Text('NOVA',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontSize: 18)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: pan == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: pan));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card number copied')));
                  },
            child: Text(shown, style: const TextStyle(color: Colors.white, fontSize: 19, letterSpacing: 1.4)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Text(revealed?['expiry'] ?? card.expiry, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (revealed != null) ...[
              const SizedBox(width: 14),
              Text('CVV ${revealed!['cvv']}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
            const SizedBox(width: 14),
            Text(card.brand.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        ]),
      ),
    );
  }
}
