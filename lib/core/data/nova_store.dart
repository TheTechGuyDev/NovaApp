import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get sb => Supabase.instance.client;

class NovaException implements Exception {
  NovaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Central app state: profile, holdings, rates and history,
/// kept live with Supabase Realtime.
class NovaStore extends ChangeNotifier {
  Profile? profile;
  final Map<String, AssetMeta> assets = {};
  final Map<String, Rate> rates = {};
  final Map<String, Map<String, dynamic>> _wallets = {};
  List<TxnItem> transactions = [];
  bool loading = false;
  String? error;

  RealtimeChannel? _channel;

  List<Holding> get holdings {
    final list = assets.values.map((meta) {
      final w = _wallets[meta.code];
      return Holding(
        walletId: w?['id'],
        meta: meta,
        balance: asDouble(w?['available']),
        locked: asDouble(w?['locked']),
        rate: rates[meta.code] ?? Rate(usd: 0, ngn: 0, change24h: 0),
      );
    }).toList()
      ..sort((a, b) => a.meta.sortOrder.compareTo(b.meta.sortOrder));
    return list;
  }

  Holding? holding(String code) {
    for (final h in holdings) {
      if (h.symbol == code) return h;
    }
    return null;
  }

  double get totalNgn => holdings.fold(0, (s, h) => s + h.valueNgn);
  double get totalUsd => holdings.fold(0, (s, h) => s + h.valueUsd);
  double get ngnPerUsd => rates['USDT']?.ngn ?? 1500;

  Future<void> loadCatalogue() async {
    final a = await sb.from('assets').select().eq('enabled', true);
    assets
      ..clear()
      ..addEntries((a as List).map((m) {
        final meta = AssetMeta.fromMap(m);
        return MapEntry(meta.code, meta);
      }));
    final r = await sb.from('rates').select();
    for (final m in r as List) {
      rates[m['asset_code']] = Rate.fromMap(m);
    }
  }

  Future<void> loadProfile() async {
    final res = await sb.rpc('my_profile');
    final list = res as List;
    profile = list.isEmpty ? null : Profile.fromMap(list.first);
    notifyListeners();
  }

  Future<void> loadAll() async {
    if (sb.auth.currentUser == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await Future.wait([loadCatalogue(), loadProfile()]);
      await Future.wait([_loadWallets(), loadTransactions(), loadVirtualAccount()]);
      _subscribe();
    } catch (e) {
      error = '$e';
      debugPrint('NovaStore.loadAll: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadWallets() async {
    final w = await sb.from('wallets').select('id, asset_code, available, locked, status');
    _wallets
      ..clear()
      ..addEntries((w as List).map((m) => MapEntry(m['asset_code'] as String, Map<String, dynamic>.from(m))));
  }

  Future<void> loadTransactions() async {
    final t = await sb
        .from('transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    transactions = (t as List).map((m) => TxnItem.fromMap(m)).toList();
  }

  void _subscribe() {
    final uid = sb.auth.currentUser?.id;
    if (uid == null || _channel != null) return;
    _channel = sb
        .channel('nova-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (p) {
            final m = p.newRecord;
            if (m.isNotEmpty) {
              _wallets[m['asset_code']] = Map<String, dynamic>.from(m);
              notifyListeners();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) async {
            await loadTransactions();
            notifyListeners();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rates',
          callback: (p) {
            final m = p.newRecord;
            if (m.isNotEmpty) {
              rates[m['asset_code']] = Rate.fromMap(m);
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  // ---------- Account actions ----------

  Future<bool> usernameAvailable(String u) async =>
      await sb.rpc('username_available', params: {'_username': u.toLowerCase()}) == true;

  Future<void> setUsername(String u) async {
    await sb.from('profiles').update({'username': u.toLowerCase()}).eq('id', sb.auth.currentUser!.id);
    await loadProfile();
  }

  Future<void> setPin(String pin, {String? oldPin}) async {
    await sb.rpc('set_transaction_pin', params: {'_pin': pin, '_old_pin': oldPin});
    await loadProfile();
  }

  /// Returns null on success, or an error message.
  Future<String?> verifyKyc(String type, String value) async {
    try {
      final res = await sb.functions.invoke('kyc-verify', body: {'type': type, 'value': value});
      final data = res.data as Map<String, dynamic>?;
      if (data?['verified'] == true) {
        await loadProfile();
        return null;
      }
      return data?['error']?.toString() ?? 'Verification failed';
    } on FunctionException catch (e) {
      final d = e.details;
      return d is Map ? (d['error']?.toString() ?? 'Verification failed') : 'Verification failed';
    } catch (e) {
      return 'Network error, please try again';
    }
  }

  // ---------- Banking ----------

  Map<String, dynamic>? virtualAccount;

  /// Calls the `banking` Edge Function. Throws [NovaException] with a readable message.
  Future<Map<String, dynamic>> banking(String action, [Map<String, dynamic> params = const {}]) =>
      _invoke('banking', action, params);

  Future<Map<String, dynamic>> crypto(String action, [Map<String, dynamic> params = const {}]) =>
      _invoke('crypto', action, params);

  List<Map<String, dynamic>> depositAddresses = [];

  Future<void> loadDepositAddresses() async {
    final r = await crypto('addresses');
    depositAddresses = List<Map<String, dynamic>>.from(r['addresses'] as List);
    notifyListeners();
  }

  /// Checks the blockchain for new deposits. Returns credited descriptions.
  Future<List<String>> syncDeposits() async {
    final r = await crypto('sync');
    await refreshMoney();
    return List<String>.from(r['credited'] as List? ?? const []);
  }

  List<TxnItem> transactionsFor(String asset) =>
      transactions.where((t) => t.asset == asset).toList();

  Future<Map<String, dynamic>> _invoke(String fn, String action, Map<String, dynamic> params) async {
    try {
      final res = await sb.functions.invoke(fn, body: {'action': action, ...params});
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      throw NovaException(d is Map ? (d['error']?.toString() ?? 'Request failed') : 'Request failed');
    } catch (e) {
      if (e is NovaException) rethrow;
      throw NovaException('Network error. Check your connection.');
    }
  }

  Future<void> loadVirtualAccount() async {
    final r = await sb.from('virtual_accounts').select().maybeSingle();
    virtualAccount = r;
    notifyListeners();
  }

  Future<void> createVirtualAccount() async {
    virtualAccount = await banking('virtual_account');
    notifyListeners();
  }

  Future<Map<String, String>?> lookupUser(String username) async {
    final r = await sb.rpc('lookup_nova_user', params: {'_username': username}) as List;
    if (r.isEmpty) return null;
    return {'username': r.first['username'], 'full_name': r.first['full_name'] ?? ''};
  }

  Future<void> refreshMoney() async {
    await Future.wait([_loadWallets(), loadTransactions()]);
    notifyListeners();
  }

  Future<void> signOut() async {
    virtualAccount = null;
    depositAddresses = [];
    await _channel?.unsubscribe();
    _channel = null;
    profile = null;
    _wallets.clear();
    transactions = [];
    await sb.auth.signOut();
    notifyListeners();
  }
}
