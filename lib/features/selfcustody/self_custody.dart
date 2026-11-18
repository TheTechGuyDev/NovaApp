import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:on_chain/on_chain.dart';
import 'package:wallet/wallet.dart' show EthereumAddress, EtherAmount;
import 'package:web3dart/web3dart.dart';

import '../../core/config.dart';
import '../../core/data/nova_store.dart';

enum ChainKind { evm, solana, bitcoin }

class ScChain {
  const ScChain({
    required this.key,
    required this.name,
    required this.symbol,
    required this.kind,
    required this.decimals,
    this.chainId,
    required this.explorerTx,
    required this.explorerAddress,
    this.canSend = true,
  });

  final String key; // wallet-rpc chain id
  final String name;
  final String symbol;
  final ChainKind kind;
  final int decimals;
  final int? chainId;
  final String explorerTx;
  final String explorerAddress;
  final bool canSend;
}

const scChains = [
  ScChain(
    key: 'ethereum-sepolia', name: 'Ethereum Sepolia', symbol: 'ETH', kind: ChainKind.evm, decimals: 18,
    chainId: 11155111,
    explorerTx: 'https://sepolia.etherscan.io/tx/{hash}',
    explorerAddress: 'https://sepolia.etherscan.io/address/{address}',
  ),
  ScChain(
    key: 'bsc-testnet', name: 'BNB Testnet', symbol: 'BNB', kind: ChainKind.evm, decimals: 18, chainId: 97,
    explorerTx: 'https://testnet.bscscan.com/tx/{hash}',
    explorerAddress: 'https://testnet.bscscan.com/address/{address}',
  ),
  ScChain(
    key: 'solana-devnet', name: 'Solana Devnet', symbol: 'SOL', kind: ChainKind.solana, decimals: 9,
    explorerTx: 'https://explorer.solana.com/tx/{hash}?cluster=devnet',
    explorerAddress: 'https://explorer.solana.com/address/{address}?cluster=devnet',
  ),
  ScChain(
    key: 'bitcoin-testnet', name: 'Bitcoin Testnet', symbol: 'BTC', kind: ChainKind.bitcoin, decimals: 8,
    explorerTx: 'https://mempool.space/testnet/tx/{hash}',
    explorerAddress: 'https://mempool.space/testnet/address/{address}',
    canSend: false,
  ),
];

/// A wallet whose keys live only on this device (or a connected external wallet).
class ScWallet {
  ScWallet({
    required this.id,
    required this.label,
    required this.source,
    required this.addresses,
    required this.createdAt,
  });

  final String id;
  String label;
  final String source; // created | imported | connected
  final Map<ChainKind, String> addresses;
  final DateTime createdAt;

  bool get watchOnly => source == 'connected';

  String? addressFor(ScChain c) => addresses[c.kind];

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'addresses': addresses.map((k, v) => MapEntry(k.name, v)),
      };

  factory ScWallet.fromJson(Map<String, dynamic> j) => ScWallet(
        id: j['id'],
        label: j['label'],
        source: j['source'],
        createdAt: DateTime.parse(j['createdAt']),
        addresses: (j['addresses'] as Map).map(
          (k, v) => MapEntry(ChainKind.values.byName(k as String), v as String),
        ),
      );
}

class _Keys {
  _Keys(this.evm, this.sol);
  final EthPrivateKey evm;
  final SolanaPrivateKey sol;
}

/// Self-custody engine. Recovery phrases are generated, stored (encrypted by the
/// platform keystore) and used for signing on this device only. The server
/// receives public addresses and already-signed transactions, never keys.
class SelfCustodyStore extends ChangeNotifier {
  // Wallet list is kept per NOVA account on this device.
  static String get _indexKey => 'nova_sc_index_v1_${sb.auth.currentUser?.id ?? 'anon'}';
  static String _seedKey(String id) => 'nova_sc_seed_$id';

  final _storage = const FlutterSecureStorage();
  final List<ScWallet> wallets = [];
  final Map<String, Map<String, double?>> balances = {}; // walletId -> chainKey -> balance
  bool loaded = false;

  // ------------------------------------------------------------ storage
  Future<void> load() async {
    if (loaded) return;
    try {
      final raw = await _storage.read(key: _indexKey);
      if (raw != null) {
        wallets
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => ScWallet.fromJson(Map<String, dynamic>.from(e))));
      }
    } catch (e) {
      debugPrint('SelfCustody.load: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _saveIndex() async {
    await _storage.write(key: _indexKey, value: jsonEncode(wallets.map((w) => w.toJson()).toList()));
  }

  // --------------------------------------------------------- phrases
  static String generatePhrase({bool words24 = false}) => Bip39MnemonicGenerator()
      .fromWordsNumber(words24 ? Bip39WordsNum.wordsNum24 : Bip39WordsNum.wordsNum12)
      .toStr();

  static String normalizePhrase(String p) =>
      p.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

  static bool isValidPhrase(String p) {
    try {
      final n = normalizePhrase(p);
      final count = n.split(' ').length;
      if (![12, 15, 18, 21, 24].contains(count)) return false;
      return Bip39MnemonicValidator().isValid(Mnemonic.fromString(n));
    } catch (_) {
      return false;
    }
  }

  static _Keys _derive(String phrase) {
    final seed = Bip39SeedGenerator(Mnemonic.fromString(phrase)).generate();
    final evm = Bip44.fromSeed(seed, Bip44Coins.ethereum)
        .purpose.coin.account(0).change(Bip44Changes.chainExt).addressIndex(0);
    final sol = Bip44.fromSeed(seed, Bip44Coins.solana).purpose.coin.account(0).change(Bip44Changes.chainExt);
    return _Keys(
      EthPrivateKey.fromHex(BytesUtils.toHexString(evm.privateKey.key.toBytes().toBytes())),
      SolanaPrivateKey.fromSeedHex(BytesUtils.toHexString(sol.privateKey.key.toBytes().toBytes())),
    );
  }

  static Map<ChainKind, String> _addresses(String phrase) {
    final seed = Bip39SeedGenerator(Mnemonic.fromString(phrase)).generate();
    final k = _derive(phrase);
    final btc = Bip84.fromSeed(seed, Bip84Coins.bitcoinTestnet)
        .purpose.coin.account(0).change(Bip44Changes.chainExt).addressIndex(0);
    return {
      ChainKind.evm: k.evm.address.eip55With0x,
      ChainKind.solana: k.sol.publicKey().toAddress().address,
      ChainKind.bitcoin: btc.publicKey.toAddress,
    };
  }

  /// Adds a wallet from a phrase (new or imported). Returns the wallet.
  Future<ScWallet> addFromPhrase(String phrase, {required String label, required String source}) async {
    final n = normalizePhrase(phrase);
    if (!isValidPhrase(n)) throw NovaException('That recovery phrase is not valid');
    final addresses = await compute(_addresses, n);
    if (wallets.any((w) => w.addresses[ChainKind.evm] == addresses[ChainKind.evm])) {
      throw NovaException('This wallet is already on this device');
    }
    final w = ScWallet(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      label: label.trim().isEmpty ? 'Wallet ${wallets.length + 1}' : label.trim(),
      source: source,
      addresses: addresses,
      createdAt: DateTime.now(),
    );
    await _storage.write(key: _seedKey(w.id), value: n);
    wallets.add(w);
    await _saveIndex();
    notifyListeners();
    _register(w);
    return w;
  }

  /// Adds a watch-only wallet connected through WalletConnect / Reown.
  Future<ScWallet> addConnected({required String label, String? evm, String? sol}) async {
    final existing = wallets.where((w) => w.watchOnly && w.addresses[ChainKind.evm] == evm && evm != null);
    if (existing.isNotEmpty) return existing.first;
    final w = ScWallet(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      label: label,
      source: 'connected',
      addresses: {if (evm != null) ChainKind.evm: evm, if (sol != null) ChainKind.solana: sol},
      createdAt: DateTime.now(),
    );
    wallets.add(w);
    await _saveIndex();
    notifyListeners();
    _register(w);
    return w;
  }

  Future<void> rename(ScWallet w, String label) async {
    w.label = label;
    await _saveIndex();
    notifyListeners();
  }

  Future<void> remove(ScWallet w) async {
    await _storage.delete(key: _seedKey(w.id));
    wallets.remove(w);
    balances.remove(w.id);
    await _saveIndex();
    notifyListeners();
    try {
      await sb.from('external_wallets').delete().eq('wallet_group', w.id);
    } catch (_) {}
  }

  /// Only call after the user has confirmed their PIN.
  Future<String> revealPhrase(ScWallet w) async {
    final p = await _storage.read(key: _seedKey(w.id));
    if (p == null) throw NovaException('Recovery phrase not found on this device');
    return p;
  }

  /// Record PUBLIC addresses so the account can show them across devices.
  Future<void> _register(ScWallet w) async {
    try {
      final rows = <Map<String, dynamic>>[];
      w.addresses.forEach((kind, address) {
        rows.add({
          'user_id': sb.auth.currentUser!.id,
          'label': w.label,
          'chain': kind.name,
          'address': address,
          'source': w.source,
          'wallet_group': w.id,
        });
      });
      await sb.from('external_wallets').upsert(rows, onConflict: 'user_id,chain,address');
    } catch (e) {
      debugPrint('register wallet: $e');
    }
  }

  // ------------------------------------------------------------ network
  Uri _rpc(String chain, {String? address}) => Uri.parse(
      '${AppConfig.supabaseUrl}/functions/v1/wallet-rpc?chain=$chain${address != null ? '&address=$address' : ''}');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${sb.auth.currentSession?.accessToken}',
      };

  Future<dynamic> _call(String chain, String method, List params) async {
    final r = await http.post(_rpc(chain),
        headers: _headers, body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}));
    final j = jsonDecode(r.body);
    if (j is Map && j['error'] != null) {
      final msg = '${j['error']['message'] ?? j['error']}';
      if (msg.toLowerCase().contains('insufficient')) {
        throw NovaException('Not enough ${chain.split('-').first.toUpperCase()} to cover the amount and network fee');
      }
      throw NovaException(msg);
    }
    return j['result'];
  }

  Future<double?> balanceOf(ScChain c, String address) async {
    try {
      switch (c.kind) {
        case ChainKind.evm:
          final hex = await _call(c.key, 'eth_getBalance', [address, 'latest']) as String;
          return BigInt.parse(hex.substring(2), radix: 16) / BigInt.from(10).pow(18);
        case ChainKind.solana:
          final r = await _call(c.key, 'getBalance', [address]);
          return (r['value'] as num) / 1e9;
        case ChainKind.bitcoin:
          final r = await http.post(_rpc(c.key, address: address), headers: _headers, body: '{}');
          return (jsonDecode(r.body)['balance'] as num?)?.toDouble();
      }
    } catch (e) {
      debugPrint('balance ${c.key}: $e');
      return null;
    }
  }

  Future<void> refreshBalances(ScWallet w) async {
    final m = <String, double?>{};
    await Future.wait(scChains.map((c) async {
      final a = w.addressFor(c);
      if (a != null) m[c.key] = await balanceOf(c, a);
    }));
    balances[w.id] = m;
    notifyListeners();
  }

  /// Estimated network fee in the chain's native coin.
  Future<double> estimateFee(ScChain c) async {
    switch (c.kind) {
      case ChainKind.evm:
        final hex = await _call(c.key, 'eth_gasPrice', []) as String;
        final gasPrice = BigInt.parse(hex.substring(2), radix: 16);
        return (gasPrice * BigInt.from(21000)) / BigInt.from(10).pow(18);
      case ChainKind.solana:
        return 0.000005;
      case ChainKind.bitcoin:
        return 0;
    }
  }

  static bool validAddress(ScChain c, String a) => switch (c.kind) {
        ChainKind.evm => RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(a),
        ChainKind.solana => RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(a),
        ChainKind.bitcoin => RegExp(r'^(tb1|[mn2])[a-zA-HJ-NP-Z0-9]{25,62}$').hasMatch(a),
      };

  /// Signs on-device and broadcasts. Returns the transaction hash / signature.
  Future<String> send(ScWallet w, ScChain c, String to, double amount) async {
    if (w.watchOnly) throw NovaException('Approve this from your connected wallet app');
    if (!c.canSend) throw NovaException('Sending ${c.symbol} from self-custody arrives in a later update');
    final phrase = await revealPhrase(w);
    final keys = _derive(phrase);

    switch (c.kind) {
      case ChainKind.evm:
        final client = Web3Client(_rpc(c.key).toString(), _AuthedClient(_headers));
        try {
          final wei = BigInt.parse((amount * 1e18).toStringAsFixed(0));
          return await client
              .sendTransaction(
            keys.evm,
            Transaction(to: EthereumAddress.fromHex(to), value: EtherAmount.inWei(wei), maxGas: 21000),
            chainId: c.chainId,
          )
              .catchError((Object e) {
            final m = '$e'.toLowerCase();
            throw NovaException(m.contains('insufficient')
                ? 'Not enough ${c.symbol} to cover the amount and gas fee'
                : 'Transaction failed: $e');
          });
        } finally {
          client.dispose();
        }
      case ChainKind.solana:
        final bh = await _call(c.key, 'getLatestBlockhash', []);
        final from = keys.sol.publicKey().toAddress();
        final tx = SolanaTransaction(
          payerKey: from,
          instructions: [
            SystemProgram.transfer(
              layout: SystemTransferLayout(lamports: BigInt.from((amount * 1e9).round())),
              from: from,
              to: SolAddress(to),
            ),
          ],
          recentBlockhash: SolAddress(bh['value']['blockhash']),
        );
        tx.sign([keys.sol]);
        final sig = await _call(c.key, 'sendTransaction', [
          tx.serializeString(encoding: TransactionSerializeEncoding.base64),
          {'encoding': 'base64'},
        ]);
        return sig as String;
      case ChainKind.bitcoin:
        throw NovaException('Not supported yet');
    }
  }

  void clear() {
    wallets.clear();
    balances.clear();
    loaded = false;
    notifyListeners();
  }
}

/// http client that adds Supabase auth headers to web3dart's JSON-RPC calls.
class _AuthedClient extends http.BaseClient {
  _AuthedClient(this.headers);
  final Map<String, String> headers;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(headers);
    return _inner.send(request);
  }
}
