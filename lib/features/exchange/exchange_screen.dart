import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  String _from = 'BTC';
  String _to = 'ETH';
  final _amount = TextEditingController(text: '0.001');

  static const double _feePct = 0.005; // illustrative 0.5% service fee

  double get _amountIn => double.tryParse(_amount.text) ?? 0;

  NovaStore get _store => context.read<NovaStore>();

  double _priceUsd(String s) => _store.holding(s)?.priceUsd ?? 0;

  double get _rate => _priceUsd(_to) == 0 ? 0 : _priceUsd(_from) / _priceUsd(_to);

  double get _received => _amountIn * _rate * (1 - _feePct);

  void _swap() => setState(() {
        final t = _from;
        _from = _to;
        _to = t;
      });

  String _fmt(String s, double v) =>
      s == 'NGN' ? formatMoney(v, symbol: '₦') : v.toStringAsFixed(v >= 100 ? 2 : 6);

  Future<void> _pick(bool isFrom) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: _store.holdings
            .map((a) => ListTile(
                  leading: CoinAvatar(symbol: a.symbol, color: a.color),
                  title: Text(a.name),
                  subtitle: Text(a.symbol),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<NovaStore>();
    final from = store.holding(_from);
    final to = store.holding(_to);
    if (from == null || to == null) return const Center(child: CircularProgressIndicator());
    final feeUsd = _amountIn * from.priceUsd * _feePct;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Row(
            children: [
              SizedBox(width: 44),
              Expanded(
                child: Center(
                  child: Text('Exchange',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
              RoundIconButton(icon: Icons.history_rounded),
            ],
          ),
          const SizedBox(height: 20),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  _SwapPanel(
                    label: 'You Pay',
                    asset: from,
                    onPick: () => _pick(true),
                    available: _fmt(from.symbol, from.balance),
                    child: TextField(
                      controller: _amount,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                    available: _fmt(to.symbol, to.balance),
                    child: Text(
                      _fmt(to.symbol, _received),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _swap,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.forest],
                    ),
                    border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor, width: 4),
                  ),
                  child: const Icon(Icons.swap_vert_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          NovaCard(
            child: Column(
              children: [
                _InfoRow('Exchange Rate', '1 $_from = ${_fmt(_to, _rate)} $_to'),
                _InfoRow('Service Fee (0.5%)', formatMoney(feeUsd, symbol: '\$')),
                _InfoRow('Network Fee', 'Calculated at confirmation'),
                const _InfoRow('Estimated Time', '~15 sec'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Demo quote. Live rates and fees arrive in Phase 7.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _amountIn <= 0
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Trading goes live in Phase 7')),
                    ),
            child: const Text('Preview Exchange'),
          ),
        ],
      ),
    );
  }
}

class _SwapPanel extends StatelessWidget {
  const _SwapPanel({
    required this.label,
    required this.asset,
    required this.onPick,
    required this.available,
    required this.child,
  });
  final String label;
  final Holding asset;
  final VoidCallback onPick;
  final String available;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Row(
                    children: [
                      CoinAvatar(symbol: asset.symbol, color: asset.color, size: 24),
                      const SizedBox(width: 6),
                      Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (!asset.isFiat) ChangeChip(asset.change24h),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Expanded(child: child),
              const SizedBox(width: 6),
              Text(asset.symbol,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ],
          ),
          Divider(height: 22, color: scheme.outline),
          Row(
            children: [
              Text('Available:',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const Spacer(),
              Text('$available ${asset.isFiat ? '' : asset.symbol}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
