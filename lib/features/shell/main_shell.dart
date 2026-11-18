import 'package:flutter/material.dart';

import '../../core/widgets/nova_widgets.dart';
import '../cards/cards_screen.dart';
import '../exchange/exchange_screen.dart';
import '../home/home_screen.dart';
import '../markets/markets_screen.dart';
import '../selfcustody/web3_home_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _icons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.swap_horiz_rounded,
    Icons.credit_card_rounded,
    Icons.account_balance_wallet_rounded,
  ];

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenExchange: () => _go(2)),
      const MarketsScreen(),
      const ExchangeScreen(),
      const CardsScreen(),
      const Web3HomeScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: IndexedStack(index: _index, children: pages),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FloatingNav(
              icons: _icons,
              index: _index,
              onTap: _go,
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.icons, required this.index, required this.onTap});
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F1311) : Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: scheme.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.5 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(icons.length, (i) {
          final selected = i == index;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2ECC71), Color(0xFF14532D)],
                      )
                    : null,
                color: selected
                    ? null
                    : (dark ? const Color(0xFF171C19) : const Color(0xFFF1F5F2)),
              ),
              child: Icon(
                icons[i],
                size: 22,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
            ),
          );
        }),
      ),
    );
  }
}
