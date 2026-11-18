import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../crypto/asset_screen.dart';
import '../insights/insights_screen.dart';
import '../kyc/kyc_screen.dart';
import '../savings/savings_screen.dart';
import '../profile/profile_screen.dart';
import '../money/add_money_screen.dart';
import '../money/bills_screen.dart';
import '../money/money_widgets.dart';
import '../money/send_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenExchange});
  final VoidCallback onOpenExchange;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hidden = false;

  void _quick(String what) {
    final page = switch (what) {
      'Send' => const SendScreen(),
      'Add Money' => const AddMoneyScreen(),
      'Bills' => const BillsScreen(),
      'Save' => const SavingsScreen(),
      'Insights' => const InsightsScreen(),
      _ => null,
    };
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$what arrives in Phase 8')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final profile = store.profile!;
    final dark = isDarkOf(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final holdings = store.holdings;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 320,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: dark ? AppColors.headerGlowDark : AppColors.headerGlowLight,
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: store.loadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const Scaffold(body: ProfileScreen(showBack: true)),
                      )),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        child: Text(profile.initials,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('@${profile.username}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    const Spacer(),
                    const RoundIconButton(icon: Icons.notifications_none_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Hello, ${profile.firstName}',
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text('Good to see you back!',
                    style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                if (profile.kycLevel < 2) ...[
                  _KycBanner(level: profile.kycLevel),
                  const SizedBox(height: 12),
                ],
                _BalanceCard(
                  hidden: _hidden,
                  totalNgn: store.totalNgn + store.totalSaved,
                  totalUsd: store.totalUsd + store.totalSaved / store.ngnPerUsd,
                  kycLevel: profile.kycLevel,
                  accountNumber: store.virtualAccount?['account_number'],
                  onAccountTap: () => _quick('Add Money'),
                  onToggle: () => setState(() => _hidden = !_hidden),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        title: 'Buy',
                        subtitle: 'Use Naira or wallet',
                        icon: Icons.add_rounded,
                        onTap: widget.onOpenExchange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        title: 'Sell',
                        subtitle: 'Convert crypto to cash',
                        icon: Icons.currency_exchange_rounded,
                        onTap: widget.onOpenExchange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _QuickActions(onTap: _quick),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _MiniStat(
                      icon: Icons.savings_rounded,
                      label: 'Savings',
                      value: formatMoney(store.totalSaved, symbol: '₦', decimals: 0),
                      onTap: () => _quick('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniStat(
                      icon: Icons.pie_chart_rounded,
                      label: 'Insights',
                      value: 'This month',
                      onTap: () => _quick('Insights'),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                const _SectionHeader(title: 'My Assets'),
                const SizedBox(height: 10),
                ...holdings.map((h) => _AssetRow(holding: h, hidden: _hidden, onOpenExchange: widget.onOpenExchange)),
                const SizedBox(height: 20),
                const _SectionHeader(title: 'Transactions'),
                const SizedBox(height: 10),
                if (store.transactions.isEmpty)
                  NovaCard(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, color: scheme.onSurfaceVariant, size: 32),
                        const SizedBox(height: 8),
                        Text('No transactions yet',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                else
                  ...store.transactions.take(10).map((t) => _TxnRow(txn: t)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KycBanner extends StatelessWidget {
  const _KycBanner({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KycScreen())),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              level == 0
                  ? 'Verify your BVN to unlock transfers and crypto'
                  : 'Verify your NIN to raise your limit to ₦5M/day',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.hidden,
    required this.onToggle,
    required this.totalNgn,
    required this.totalUsd,
    required this.kycLevel,
    required this.accountNumber,
    required this.onAccountTap,
  });
  final String? accountNumber;
  final VoidCallback onAccountTap;
  final bool hidden;
  final VoidCallback onToggle;
  final double totalNgn;
  final double totalUsd;
  final int kycLevel;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text('Total Portfolio',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
              const Spacer(),
              const Text('NOVA',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      fontSize: 18)),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    hidden ? '₦ ••••••' : formatMoney(totalNgn, symbol: '₦'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.white.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hidden ? '≈ \$ ••••' : '≈ ${formatMoney(totalUsd, symbol: '\$')}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              GestureDetector(
                onTap: onAccountTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Naira Account', style: TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(accountNumber ?? 'Get account number  ›',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                  ],
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('KYC Tier', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('Level $kycLevel',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline),
              ),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
          ),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const items = [
      (Icons.north_east_rounded, 'Send'),
      (Icons.add_rounded, 'Add Money'),
      (Icons.receipt_long_rounded, 'Bills'),
      (Icons.savings_rounded, 'Save'),
    ];
    return NovaCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map((e) => InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(e.$2),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(e.$1, color: scheme.primary, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(e.$2,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16));
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.holding, required this.hidden, required this.onOpenExchange});
  final Holding holding;
  final bool hidden;
  final VoidCallback onOpenExchange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = holding;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovaCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AssetScreen(symbol: h.symbol, onOpenExchange: onOpenExchange),
        )),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CoinAvatar(symbol: h.symbol, color: h.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(hidden ? '••••' : h.balanceLabel,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hidden ? '••••' : formatMoney(h.valueNgn, symbol: '₦'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (!h.isFiat) ...[
                  const SizedBox(height: 4),
                  ChangeChip(h.change24h),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn});
  final TxnItem txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = txn.incoming ? AppColors.success : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovaCard(
        onTap: () => showTxnDetails(context, txn),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(txn.icon, size: 20, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text('${friendlyDate(txn.createdAt)} · ${txn.status}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Text(txn.amountLabel, style: TextStyle(fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }
}


class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}
