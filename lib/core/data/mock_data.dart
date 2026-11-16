import 'package:flutter/material.dart';

/// Phase 1 demo data. Replaced by Supabase + live prices in later phases.

class Asset {
  const Asset({
    required this.symbol,
    required this.name,
    required this.balance,
    required this.priceUsd,
    required this.change24h,
    required this.color,
    this.isFiat = false,
  });

  final String symbol;
  final String name;
  final double balance;
  final double priceUsd;
  final double change24h;
  final Color color;
  final bool isFiat;

  double get valueUsd => balance * priceUsd;
}

class Txn {
  const Txn({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.incoming,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String amount;
  final bool incoming;
  final IconData icon;
}

class MockData {
  MockData._();

  /// Illustrative NGN per USD rate for the demo.
  static const double ngnPerUsd = 1500;

  static const List<Asset> assets = [
    Asset(
      symbol: 'NGN',
      name: 'Naira',
      balance: 850000,
      priceUsd: 1 / ngnPerUsd,
      change24h: 0,
      color: Color(0xFF22C55E),
      isFiat: true,
    ),
    Asset(
      symbol: 'USDT',
      name: 'Tether',
      balance: 800,
      priceUsd: 1,
      change24h: 0.01,
      color: Color(0xFF26A17B),
    ),
    Asset(
      symbol: 'BTC',
      name: 'Bitcoin',
      balance: 0.0031,
      priceUsd: 96500,
      change24h: 3.48,
      color: Color(0xFFF7931A),
    ),
    Asset(
      symbol: 'ETH',
      name: 'Ethereum',
      balance: 0.058,
      priceUsd: 3450,
      change24h: 5.67,
      color: Color(0xFF8C8CF7),
    ),
    Asset(
      symbol: 'USDC',
      name: 'USD Coin',
      balance: 120,
      priceUsd: 1,
      change24h: 0.0,
      color: Color(0xFF2775CA),
    ),
    Asset(
      symbol: 'SOL',
      name: 'Solana',
      balance: 1.2,
      priceUsd: 182,
      change24h: -1.92,
      color: Color(0xFF14F195),
    ),
    Asset(
      symbol: 'BNB',
      name: 'BNB',
      balance: 0.4,
      priceUsd: 640,
      change24h: 0.84,
      color: Color(0xFFF3BA2F),
    ),
  ];

  static double get totalUsd =>
      assets.fold(0, (sum, a) => sum + a.valueUsd);

  static double get totalNgn => totalUsd * ngnPerUsd;

  static Asset bySymbol(String s) => assets.firstWhere((a) => a.symbol == s);

  static const List<Txn> transactions = [
    Txn(
      title: 'Transfer to Firmansyah A.',
      subtitle: 'Today, 09:14',
      amount: '-₦20,000',
      incoming: false,
      icon: Icons.north_east_rounded,
    ),
    Txn(
      title: 'Received USDT',
      subtitle: 'Yesterday, 18:02 · TRC20',
      amount: '+150 USDT',
      incoming: true,
      icon: Icons.south_west_rounded,
    ),
    Txn(
      title: 'Sold BTC for Naira',
      subtitle: '14 Nov, 11:40',
      amount: '+₦145,200',
      incoming: true,
      icon: Icons.swap_horiz_rounded,
    ),
    Txn(
      title: 'MTN Airtime',
      subtitle: '13 Nov, 08:21',
      amount: '-₦2,000',
      incoming: false,
      icon: Icons.phone_android_rounded,
    ),
    Txn(
      title: 'Ikeja Electric',
      subtitle: '12 Nov, 20:55',
      amount: '-₦15,000',
      incoming: false,
      icon: Icons.bolt_rounded,
    ),
  ];
}

String formatMoney(double v, {String symbol = '', int decimals = 2}) {
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  final sign = v < 0 ? '-' : '';
  return decimals > 0 ? '$sign$symbol$whole.${parts[1]}' : '$sign$symbol$whole';
}
