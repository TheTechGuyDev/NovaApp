import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';
import 'create_wallet_screen.dart';
import 'self_custody.dart';
import 'wallet_connect.dart';
import 'wallet_detail_screen.dart';

/// Tab 5: self-custody wallets (keys on device) and connected external wallets.
class Web3HomeScreen extends StatefulWidget {
  const Web3HomeScreen({super.key});
  @override
  State<Web3HomeScreen> createState() => _Web3HomeScreenState();
}

class _Web3HomeScreenState extends State<Web3HomeScreen> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    context.read<SelfCustodyStore>().load();
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _connect() async {
    final sc = context.read<SelfCustodyStore>();
    setState(() => _connecting = true);
    try {
      final r = await WalletConnectService().connect(context);
      if (r == null || (r.evm == null && r.sol == null)) return;
      final w = await sc.addConnected(label: r.walletName ?? 'Connected wallet', evm: r.evm, sol: r.sol);
      if (mounted) _open(WalletDetailScreen(wallet: w));
    } catch (e) {
      if (mounted) showError(context, 'Could not connect wallet: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SelfCustodyStore>();
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Center(
            child: Text('Web3 Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.key_rounded, color: Colors.white, size: 28),
                SizedBox(height: 12),
                Text('Your keys, your crypto',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text(
                  'Self-custody wallets keep the recovery phrase on this device only. '
                  'NOVA can never see it or move your funds.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _Action(
                icon: Icons.add_circle_outline_rounded,
                label: 'Create',
                onTap: () => _open(const CreateWalletScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Action(
                icon: Icons.download_rounded,
                label: 'Import',
                onTap: () => _open(const ImportWalletScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Action(
                icon: Icons.link_rounded,
                label: _connecting ? 'Opening...' : 'Connect',
                onTap: _connecting ? null : _connect,
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Text('My wallets', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          if (!sc.loaded)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (sc.wallets.isEmpty)
            NovaCard(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(children: [
                Icon(Icons.account_balance_wallet_outlined, size: 34, color: scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text('No self-custody wallets yet', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('Create one, import a recovery phrase, or connect MetaMask, Trust or Phantom.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ]),
            )
          else
            ...sc.wallets.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NovaCard(
                    onTap: () => _open(WalletDetailScreen(wallet: w)),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(w.watchOnly ? Icons.link_rounded : Icons.key_rounded, color: scheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(w.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '${shortAddress(w.addresses[ChainKind.evm] ?? w.addresses.values.first)} · '
                            '${switch (w.source) { 'created' => 'Created here', 'imported' => 'Imported', _ => 'Connected' }}',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                    ]),
                  ),
                )),
          const SizedBox(height: 10),
          Text('Testnets: Ethereum Sepolia · BNB Testnet · Solana Devnet · Bitcoin Testnet',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

String shortAddress(String a) => a.length > 14 ? '${a.substring(0, 6)}...${a.substring(a.length - 4)}' : a;

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// Keep formatCrypto reachable for files that import this one.
String fmtCoin(double? v) => v == null ? '...' : formatCrypto(v);
