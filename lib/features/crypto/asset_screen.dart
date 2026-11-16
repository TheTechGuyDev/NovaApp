import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/add_money_screen.dart';
import '../money/money_widgets.dart';
import '../money/send_screen.dart';
import 'receive_crypto_screen.dart';
import 'send_crypto_screen.dart';

/// Detail page for one asset: balance, actions and its own history.
class AssetScreen extends StatelessWidget {
  const AssetScreen({super.key, required this.symbol, this.onOpenExchange});
  final String symbol;
  final VoidCallback? onOpenExchange;

  void _go(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _faucet(BuildContext context) async {
    final store = context.read<NovaStore>();
    try {
      final r = await store.crypto('test_faucet', {'asset': symbol});
      await store.refreshMoney();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${r['amount']} test $symbol')),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final h = store.holding(symbol)!;
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);
    final history = store.transactionsFor(symbol);

    final actions = <(IconData, String, VoidCallback)>[
      if (h.isFiat) ...[
        (Icons.add_rounded, 'Add', () => _go(context, const AddMoneyScreen())),
        (Icons.north_east_rounded, 'Send', () => _go(context, const SendScreen())),
      ] else ...[
        (Icons.south_west_rounded, 'Receive', () => _go(context, ReceiveCryptoScreen(symbol: symbol))),
        (Icons.north_east_rounded, 'Send', () => _go(context, SendCryptoScreen(symbol: symbol))),
      ],
      if (onOpenExchange != null)
        (Icons.swap_horiz_rounded, 'Swap', () {
          Navigator.pop(context);
          onOpenExchange!();
        }),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(h.name)),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!h.isFiat) await store.syncDeposits();
          await store.refreshMoney();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CoinAvatar(symbol: symbol, color: Colors.white, size: 40),
                    const SizedBox(width: 12),
                    Text(h.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (!h.isFiat) ChangeChip(h.change24h),
                  ]),
                  const SizedBox(height: 20),
                  Text(h.balanceLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    h.isFiat
                        ? '≈ ${formatMoney(h.valueUsd, symbol: '\$')}'
                        : '≈ ${formatMoney(h.valueNgn, symbol: '₦')} · 1 $symbol = ${formatMoney(h.priceNgn, symbol: '₦')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: actions
                  .map((a) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: NovaCard(
                            onTap: a.$3,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Column(children: [
                              Icon(a.$1, color: scheme.primary),
                              const SizedBox(height: 6),
                              Text(a.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            if (!h.isFiat && AppConfig.environment == 'sandbox') ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _faucet(context),
                icon: const Icon(Icons.science_outlined, size: 18),
                label: Text('Get test $symbol (sandbox faucet)'),
              ),
            ],
            const SizedBox(height: 18),
            const Text('History', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 10),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No $symbol transactions yet', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              )
            else
              ...history.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NovaCard(
                      onTap: () => showTxnDetails(context, t),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Icon(t.icon, color: scheme.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500)),
                            Text('${friendlyDate(t.createdAt)} · ${t.status}',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          ]),
                        ),
                        Text(t.amountLabel,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: t.incoming ? AppColors.success : scheme.onSurface)),
                      ]),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
