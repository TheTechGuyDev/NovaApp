import 'package:flutter/material.dart';

Color hexColor(String? hex, {Color fallback = const Color(0xFF22C55E)}) {
  if (hex == null || hex.length < 7) return fallback;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

double asDouble(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

class Profile {
  Profile({
    required this.id,
    this.fullName,
    this.username,
    this.phone,
    this.email,
    required this.kycLevel,
    required this.status,
    required this.hasPin,
    this.referralCode,
  });

  final String id;
  final String? fullName;
  final String? username;
  final String? phone;
  final String? email;
  final int kycLevel;
  final String status;
  final bool hasPin;
  final String? referralCode;

  bool get isSetupComplete => username != null && hasPin;

  String get firstName {
    final n = (fullName ?? '').trim();
    if (n.isEmpty) return username ?? 'there';
    return n.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = (fullName ?? username ?? '?').trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'],
        fullName: m['full_name'],
        username: m['username'],
        phone: m['phone'],
        email: m['email'],
        kycLevel: (m['kyc_level'] as num?)?.toInt() ?? 0,
        status: m['status'] ?? 'active',
        hasPin: m['has_pin'] == true,
        referralCode: m['referral_code'],
      );
}

class AssetMeta {
  AssetMeta({
    required this.code,
    required this.name,
    required this.isFiat,
    required this.decimals,
    required this.color,
    required this.sortOrder,
  });

  final String code;
  final String name;
  final bool isFiat;
  final int decimals;
  final Color color;
  final int sortOrder;

  factory AssetMeta.fromMap(Map<String, dynamic> m) => AssetMeta(
        code: m['code'],
        name: m['name'],
        isFiat: m['type'] == 'fiat',
        decimals: (m['decimals'] as num).toInt(),
        color: hexColor(m['icon_color']),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 100,
      );
}

class Rate {
  Rate({required this.usd, required this.ngn, required this.change24h});
  final double usd;
  final double ngn;
  final double change24h;

  factory Rate.fromMap(Map<String, dynamic> m) => Rate(
        usd: asDouble(m['usd_price']),
        ngn: asDouble(m['ngn_price']),
        change24h: asDouble(m['change_24h']),
      );
}

/// A wallet joined with its asset metadata and current rate.
class Holding {
  Holding({
    required this.walletId,
    required this.meta,
    required this.balance,
    required this.locked,
    required this.rate,
  });

  final String? walletId;
  final AssetMeta meta;
  final double balance;
  final double locked;
  final Rate rate;

  String get symbol => meta.code;
  String get name => meta.name;
  bool get isFiat => meta.isFiat;
  Color get color => meta.color;
  double get priceUsd => rate.usd;
  double get priceNgn => rate.ngn;
  double get change24h => rate.change24h;
  double get valueUsd => balance * rate.usd;
  double get valueNgn => balance * rate.ngn;

  String get balanceLabel => isFiat
      ? formatMoney(balance, symbol: '₦')
      : '${formatCrypto(balance)} $symbol';
}

class TxnItem {
  TxnItem({
    required this.id,
    required this.type,
    required this.status,
    required this.asset,
    required this.amount,
    required this.fee,
    required this.reference,
    required this.title,
    required this.createdAt,
    this.counterparty = const {},
    this.metadata = const {},
  });

  final Map<String, dynamic> counterparty;
  final Map<String, dynamic> metadata;
  final String id;
  final String type;
  final String status;
  final String asset;
  final double amount;
  final double fee;
  final String reference;
  final String title;
  final DateTime createdAt;

  bool get incoming =>
      const ['deposit', 'transfer_in', 'reversal'].contains(type) ||
      (type == 'conversion' && amount > 0) ||
      (type == 'trade' && amount > 0);

  IconData get icon => switch (type) {
        'deposit' || 'transfer_in' => Icons.south_west_rounded,
        'withdrawal' || 'transfer_out' => Icons.north_east_rounded,
        'bill_payment' => Icons.receipt_long_rounded,
        'conversion' || 'trade' => Icons.swap_horiz_rounded,
        _ => Icons.sync_alt_rounded,
      };

  String get amountLabel {
    final sign = incoming ? '+' : '-';
    final v = amount.abs();
    return asset == 'NGN'
        ? '$sign${formatMoney(v, symbol: '₦')}'
        : '$sign${formatCrypto(v)} $asset';
  }

  factory TxnItem.fromMap(Map<String, dynamic> m) => TxnItem(
        id: m['id'],
        type: m['type'],
        status: m['status'],
        asset: m['asset_code'],
        amount: asDouble(m['amount']),
        fee: asDouble(m['fee']),
        reference: m['reference'],
        title: m['title'] ?? (m['type'] as String).replaceAll('_', ' '),
        createdAt: DateTime.parse(m['created_at']).toLocal(),
        counterparty: Map<String, dynamic>.from(m['counterparty'] ?? const {}),
        metadata: Map<String, dynamic>.from(m['metadata'] ?? const {}),
      );
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

String formatCrypto(double v) {
  if (v == 0) return '0';
  if (v >= 1000) return formatMoney(v);
  if (v >= 1) return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return v.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String friendlyDate(DateTime d) {
  final now = DateTime.now();
  final t = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (DateUtils.isSameDay(d, now)) return 'Today, $t';
  if (DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday, $t';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}, $t';
}
