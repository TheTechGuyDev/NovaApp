import 'package:flutter/material.dart';

import '../../core/data/mock_data.dart';
import '../../core/widgets/nova_widgets.dart';

class MarketsScreen extends StatelessWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coins = MockData.assets.where((a) => !a.isFiat).toList();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Center(
            child: Text('Markets',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search assets',
              prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          ...coins.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NovaCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    CoinAvatar(symbol: a.symbol, color: a.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(a.symbol,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatMoney(a.priceUsd, symbol: '\$'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        ChangeChip(a.change24h),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
