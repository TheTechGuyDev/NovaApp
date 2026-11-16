import 'package:flutter/material.dart';

import '../../core/data/mock_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenExchange});
  final VoidCallback onOpenExchange;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: const Text('T',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  ),
                  const Spacer(),
                  const RoundIconButton(icon: Icons.notifications_none_rounded),
                ],
              ),
              const SizedBox(height: 14),
              Text('Hello, Temidayo',
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              Text('Good to see you back!',
                  style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              _BalanceCard(
                hidden: _hidden,
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
              const _QuickActions(),
              const SizedBox(height: 24),
              _SectionHeader(title: 'My Assets', action: 'See all'),
              const SizedBox(height: 10),
              ...MockData.assets.take(4).map((a) => _AssetRow(asset: a, hidden: _hidden)),
              const SizedBox(height: 20),
              _SectionHeader(title: 'Transactions', action: 'See all'),
              const SizedBox(height: 10),
              ...MockData.transactions.map((t) => _TxnRow(txn: t)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.hidden, required this.onToggle});
  final bool hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final total = MockData.totalNgn;
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
                child: const Text('Main Wallet',
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
          const Text('Total Balance',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    hidden ? '₦ ••••••' : formatMoney(total, symbol: '₦'),
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
            hidden ? '≈ \$ ••••' : '≈ ${formatMoney(MockData.totalUsd, symbol: '\$')}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account Number',
                      style: TextStyle(color: Colors.white60, fontSize: 11)),
                  SizedBox(height: 2),
                  Text('**** 9000',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ],
              ),
              Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Tier', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  SizedBox(height: 2),
                  Text('Level 2',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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
          Text(subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const items = [
      (Icons.north_east_rounded, 'Send'),
      (Icons.south_west_rounded, 'Receive'),
      (Icons.receipt_long_rounded, 'Bills'),
      (Icons.savings_rounded, 'Save'),
    ];
    return NovaCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map((e) => Column(
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
                ))
            .toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const Spacer(),
        Text(action, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset, required this.hidden});
  final Asset asset;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bal = asset.isFiat
        ? formatMoney(asset.balance, symbol: '₦')
        : '${asset.balance} ${asset.symbol}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovaCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CoinAvatar(symbol: asset.symbol, color: asset.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(hidden ? '••••' : bal,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hidden ? '••••' : formatMoney(asset.valueUsd, symbol: '\$'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (!asset.isFiat) ...[
                  const SizedBox(height: 4),
                  ChangeChip(asset.change24h),
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
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = txn.incoming ? AppColors.success : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovaCard(
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
                  Text(txn.subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Text(txn.amount,
                style: TextStyle(fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }
}
