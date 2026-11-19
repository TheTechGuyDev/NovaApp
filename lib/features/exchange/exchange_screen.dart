import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';

/// Set by Home's Buy/Sell buttons before switching to the Exchange tab.
final exchangePreset = ValueNotifier<(String, String)?>(null);

String fmtAsset(String code, double v) => code == 'NGN' ? formatMoney(v, symbol: '₦') : '${formatCrypto(v)} $code';

/// Human rate: always "1 crypto = X" (Naira buys show the coin's Naira price).
String rateLabel(String from, String to, double rate) {
  if (rate <= 0) return '-';
  if (from == 'NGN') return '1 $to = ${formatMoney(1 / rate, symbol: '₦')}';
  if (to == 'NGN') return '1 $from = ${formatMoney(rate, symbol: '₦')}';
  return '1 $from = ${formatCrypto(rate)} $to';
}

class ExchangeScreen extends StatelessWidget {
  const ExchangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          const SizedBox(height: 12),
          const Text('Exchange', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const TabBar(tabs: [Tab(text: 'Instant Swap'), Tab(text: 'Limit Orders')]),
          const Expanded(child: TabBarView(children: [_SwapTab(), _LimitTab()])),
        ]),
      ),
    );
  }
}

// ================================================================ SWAP
class _SwapTab extends StatefulWidget {
  const _SwapTab();
  @override
  State<_SwapTab> createState() => _SwapTabState();
}

class _SwapTabState extends State<_SwapTab> with AutomaticKeepAliveClientMixin {
  String _from = 'NGN';
  String _to = 'USDT';
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    exchangePreset.addListener(_applyPreset);
    _applyPreset();
  }

  @override
  void dispose() {
    exchangePreset.removeListener(_applyPreset);
    super.dispose();
  }

  void _applyPreset() {
    final p = exchangePreset.value;
    if (p == null) return;
    setState(() {
      _from = p.$1;
      _to = p.$2;
      _amount.clear();
    });
    exchangePreset.value = null;
  }

  double get _amountIn => double.tryParse(_amount.text) ?? 0;

  void _swap() => setState(() {
        final t = _from;
        _from = _to;
        _to = t;
        _amount.clear();
      });

  Future<void> _pick(bool isFrom) async {
    final store = context.read<NovaStore>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: store.holdings
            .map((a) => ListTile(
                  leading: CoinAvatar(symbol: a.symbol, color: a.color),
                  title: Text(a.name),
                  subtitle: Text(a.balanceLabel),
                  trailing: Text(formatMoney(a.priceNgn, symbol: '₦'), style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(context, a.symbol),
                ))
            .toList(),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        if (picked == _to) _to = _from;
        _from = picked;
      } else {
        if (picked == _from) _from = _to;
        _to = picked;
      }
    });
  }

  Future<void> _preview() async {
    final store = context.read<NovaStore>();
    setState(() => _busy = true);
    try {
      final q = Map<String, dynamic>.from(await store.rpc('exchange_quote', {
        '_from': _from,
        '_to': _to,
        '_amount_in': _amountIn,
      }) as Map);
      if (!mounted) return;
      final done = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _QuoteSheet(quote: q),
      );
      if (done != null && mounted) {
        final from = _from, to = _to;
        _amount.clear();
        await store.refreshMoney();
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            title: to == 'NGN' ? 'Sold $from' : (from == 'NGN' ? 'Bought $to' : 'Swap complete'),
            amount: fmtAsset(to, asDouble(done['amount_out'])),
            rows: [
              ('Paid', fmtAsset(from, asDouble(q['amount_in']))),
              ('Rate', rateLabel(from, to, asDouble(q['rate']))),
              ('Fee (${asDouble(q['fee_pct']).toStringAsFixed(2)}%)', fmtAsset(to, asDouble(q['fee']))),
              ('Reference', '${done['reference']}'),
            ],
          ),
        ));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = context.watch<NovaStore>();
    final scheme = Theme.of(context).colorScheme;
    final from = store.holding(_from);
    final to = store.holding(_to);
    if (from == null || to == null) return const Center(child: CircularProgressIndicator());

    final rate = to.priceNgn == 0 ? 0.0 : from.priceNgn / to.priceNgn;
    const feePct = 0.5;
    final estOut = _amountIn * rate * (1 - feePct / 100);
    final ngnValue = _amountIn * from.priceNgn;
    final ok = _amountIn > 0 && _amountIn <= from.balance + 1e-12 && ngnValue >= 500 && !_busy;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Column(children: [
              _SwapPanel(
                label: 'You Pay',
                asset: from,
                onPick: () => _pick(true),
                onMax: () => setState(() => _amount.text = from.isFiat
                    ? from.balance.toStringAsFixed(2)
                    : formatCrypto(from.balance).replaceAll(',', '')),
                child: TextField(
                  controller: _amount,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'))],
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '0.00',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _SwapPanel(
                label: 'You Receive',
                asset: to,
                onPick: () => _pick(false),
                child: Text(
                  _amountIn == 0 ? '0.00' : (to.isFiat ? formatMoney(estOut) : formatCrypto(estOut)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            GestureDetector(
              onTap: _swap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.forest]),
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 4),
                ),
                child: const Icon(Icons.swap_vert_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        NovaCard(
          child: Column(children: [
            DetailRow('Exchange rate', rateLabel(_from, _to, rate)),
            DetailRow('Fee', '${feePct.toStringAsFixed(2)}%'),
            DetailRow('Value', formatMoney(ngnValue, symbol: '₦')),
            const DetailRow('Settlement', 'Instant'),
          ]),
        ),
        const SizedBox(height: 8),
        if (_amountIn > from.balance + 1e-12)
          Text('Insufficient ${from.symbol} balance', style: TextStyle(color: scheme.error, fontSize: 12))
        else if (_amountIn > 0 && ngnValue < 500)
          Text('Minimum trade is ₦500', style: TextStyle(color: scheme.error, fontSize: 12))
        else
          Text('Live market price. Your final quote is locked for 30 seconds.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: ok ? _preview : null,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_to == 'NGN' ? 'Sell $_from' : (_from == 'NGN' ? 'Buy $_to' : 'Swap')),
        ),
      ],
    );
  }
}

class _QuoteSheet extends StatefulWidget {
  const _QuoteSheet({required this.quote});
  final Map<String, dynamic> quote;
  @override
  State<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<_QuoteSheet> {
  late Map<String, dynamic> q = widget.quote;
  Timer? _timer;
  int _left = 30;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    final exp = DateTime.parse(q['expires_at']).toLocal();
    _left = exp.difference(DateTime.now()).inSeconds.clamp(0, 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = exp.difference(DateTime.now()).inSeconds.clamp(0, 30));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      q = Map<String, dynamic>.from(await context.read<NovaStore>().rpc('exchange_quote', {
        '_from': q['from'],
        '_to': q['to'],
        '_amount_in': asDouble(q['amount_in']),
      }) as Map);
      _tick();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final pin = await askPin(context, title: 'Confirm trade');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await context.read<NovaStore>().rpc('exchange_execute', {'_quote': q['id'], '_pin': pin});
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = q['from'] as String;
    final to = q['to'] as String;
    final expired = _left <= 0;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Confirm your trade',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Text('You receive', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          Text(fmtAsset(to, asDouble(q['amount_out'])),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          NovaCard(
            child: Column(children: [
              DetailRow('You pay', fmtAsset(from, asDouble(q['amount_in']))),
              DetailRow('Rate', rateLabel(from, to, asDouble(q['rate']))),
              DetailRow('Fee (${asDouble(q['fee_pct']).toStringAsFixed(2)}%)', fmtAsset(to, asDouble(q['fee']))),
              const DetailRow('Network fee', 'None (internal settlement)'),
              const DetailRow('Processing time', 'Instant'),
            ]),
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.timer_outlined, size: 16, color: expired ? scheme.error : scheme.primary),
            const SizedBox(width: 6),
            Text(expired ? 'Quote expired' : 'Price locked for ${_left}s',
                style: TextStyle(color: expired ? scheme.error : scheme.primary, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : (expired ? _refresh : _confirm),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(expired ? 'Get new price' : 'Confirm'),
          ),
        ]),
      ),
    );
  }
}

class _SwapPanel extends StatelessWidget {
  const _SwapPanel({required this.label, required this.asset, required this.onPick, required this.child, this.onMax});
  final String label;
  final Holding asset;
  final VoidCallback onPick;
  final VoidCallback? onMax;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(children: [
        Row(children: [
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: scheme.outline)),
              child: Row(children: [
                CoinAvatar(symbol: asset.symbol, color: asset.color, size: 24),
                const SizedBox(width: 6),
                Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ]),
            ),
          ),
          const Spacer(),
          if (!asset.isFiat) ChangeChip(asset.change24h),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(child: child),
          const SizedBox(width: 6),
          Text(asset.symbol, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ]),
        Divider(height: 22, color: scheme.outline),
        Row(children: [
          Text('Available:', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          const Spacer(),
          Text(asset.balanceLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          if (onMax != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onMax,
              child: Text('MAX', style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ]),
    );
  }
}

// =============================================================== LIMIT
class _LimitTab extends StatefulWidget {
  const _LimitTab();
  @override
  State<_LimitTab> createState() => _LimitTabState();
}

class _LimitTabState extends State<_LimitTab> with AutomaticKeepAliveClientMixin {
  String _pair = 'USDT_NGN';
  String _side = 'buy';
  final _price = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;
  List<Map<String, dynamic>> _depth = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final store = context.read<NovaStore>();
    store.loadPairs();
    store.loadOrders();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setMarketPrice());
  }

  Map<String, dynamic>? get _p => context.read<NovaStore>().pairs.where((x) => x['symbol'] == _pair).firstOrNull;

  double _market(NovaStore s) {
    final parts = _pair.split('_');
    final b = s.holding(parts[0])?.priceNgn ?? 0;
    final q = s.holding(parts[1])?.priceNgn ?? 0;
    return q == 0 ? 0 : b / q;
  }

  String _fmtPrice(double v) =>
      v >= 100 ? v.toStringAsFixed(2) : v.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');

  void _setMarketPrice() {
    final m = _market(context.read<NovaStore>());
    if (m > 0) setState(() => _price.text = _fmtPrice(m));
    _loadDepth();
  }

  Future<void> _loadDepth() async {
    try {
      final r = await context.read<NovaStore>().rpc('exchange_depth', {'_pair': _pair}) as List;
      if (mounted) setState(() => _depth = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  Future<void> _place() async {
    final store = context.read<NovaStore>();
    final parts = _pair.split('_');
    final price = double.parse(_price.text);
    final amount = double.parse(_amount.text);
    final pin = await askPin(context,
        title: 'Place limit order',
        subtitle:
            '${_side == 'buy' ? 'Buy' : 'Sell'} ${formatCrypto(amount)} ${parts[0]} at ${_fmtPrice(price)} ${parts[1]}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await store.rpc('exchange_place_limit', {
        '_pair': _pair,
        '_side': _side,
        '_price': price,
        '_amount': amount,
        '_pin': pin,
      });
      _amount.clear();
      await Future.wait([store.loadOrders(), store.refreshMoney()]);
      _loadDepth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order placed. It fills automatically when the market reaches your price.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> o) async {
    final store = context.read<NovaStore>();
    try {
      await store.rpc('exchange_cancel', {'_order': o['id']});
      await Future.wait([store.loadOrders(), store.refreshMoney()]);
      _loadDepth();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = context.watch<NovaStore>();
    final scheme = Theme.of(context).colorScheme;
    final parts = _pair.split('_');
    final base = parts[0], quote = parts[1];
    final price = double.tryParse(_price.text) ?? 0;
    final amount = double.tryParse(_amount.text) ?? 0;
    final total = price * amount;
    final market = _market(store);
    final feePct = asDouble(_p?['fee_pct'] ?? 0.5);
    final spendAsset = _side == 'buy' ? quote : base;
    final spend = _side == 'buy' ? total : amount;
    final available = store.holding(spendAsset)?.balance ?? 0;
    final ok = price > 0 && amount > 0 && spend <= available + 1e-12 && !_busy;
    final open = store.orders.where((o) => o['status'] == 'open' || o['status'] == 'partially_filled').toList();
    final history = store.orders.where((o) => !(o['status'] == 'open' || o['status'] == 'partially_filled')).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await store.loadOrders();
        await _loadDepth();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _pair,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Market', isDense: true),
                items: (store.pairs.isEmpty ? [<String, dynamic>{'symbol': _pair}] : store.pairs)
                    .map((p) => DropdownMenuItem(
                          value: p['symbol'] as String,
                          child: Text((p['symbol'] as String).replaceAll('_', ' / ')),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _pair = v);
                  _setMarketPrice();
                },
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Market price', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
              Text('${_fmtPrice(market)} $quote', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ]),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'buy', label: Text('Buy')),
              ButtonSegment(value: 'sell', label: Text('Sell')),
            ],
            selected: {_side},
            onSelectionChanged: (s) => setState(() => _side = s.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _price,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'))],
            decoration: InputDecoration(
              labelText: 'Limit price ($quote per $base)',
              suffixIcon: TextButton(onPressed: _setMarketPrice, child: const Text('Market')),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'))],
            decoration: InputDecoration(labelText: 'Amount ($base)', suffixText: base),
          ),
          const SizedBox(height: 10),
          NovaCard(
            child: Column(children: [
              DetailRow('Total', fmtAsset(quote, total)),
              DetailRow('Fee', '${feePct.toStringAsFixed(2)}% on fill'),
              DetailRow('Available', fmtAsset(spendAsset, available)),
              DetailRow('Fills when',
                  _side == 'buy' ? 'Price drops to ${_fmtPrice(price)} or below' : 'Price rises to ${_fmtPrice(price)} or above'),
            ]),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _side == 'sell' ? AppColors.danger : null),
            onPressed: ok ? _place : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('${_side == 'buy' ? 'Buy' : 'Sell'} $base'),
          ),
          const SizedBox(height: 22),
          const Text('Order book (open orders)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          if (_depth.isEmpty)
            Text('No open orders on this market yet', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
          else
            NovaCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(children: [
                for (final d in _depth)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Text(_fmtPrice(asDouble(d['price'])),
                          style: TextStyle(
                              color: d['side'] == 'buy' ? AppColors.success : AppColors.danger,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${formatCrypto(asDouble(d['amount']))} $base', style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
              ]),
            ),
          const SizedBox(height: 22),
          Text('Open orders (${open.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          if (open.isEmpty)
            Text('No open orders', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
          else
            ...open.map((o) => _OrderTile(order: o, onCancel: () => _cancel(o))),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Order history', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            ...history.take(20).map((o) => _OrderTile(order: o)),
          ],
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, this.onCancel});
  final Map<String, dynamic> order;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = (order['pair'] as String).split('_');
    final buy = order['side'] == 'buy';
    final status = order['status'] as String;
    final price = asDouble(order['price']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovaCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (buy ? AppColors.success : AppColors.danger).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(buy ? 'BUY' : 'SELL',
                style: TextStyle(
                    color: buy ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w700, fontSize: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${formatCrypto(asDouble(order['amount']))} ${parts[0]}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '@ ${price >= 100 ? formatMoney(price) : formatCrypto(price)} ${parts[1]} · '
                '${friendlyDate(DateTime.parse(order['created_at']).toLocal())}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ]),
          ),
          if (onCancel != null)
            TextButton(onPressed: onCancel, child: const Text('Cancel'))
          else
            Text(status[0].toUpperCase() + status.substring(1),
                style: TextStyle(
                  color: status == 'filled' ? AppColors.success : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                )),
        ]),
      ),
    );
  }
}
