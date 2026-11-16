import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';

class ReceiveCryptoScreen extends StatefulWidget {
  const ReceiveCryptoScreen({super.key, required this.symbol});
  final String symbol;
  @override
  State<ReceiveCryptoScreen> createState() => _ReceiveCryptoScreenState();
}

class _ReceiveCryptoScreenState extends State<ReceiveCryptoScreen> {
  String? _networkId;
  bool _loading = false;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<NovaStore>();
    if (store.depositAddresses.isNotEmpty) return _pickDefault();
    setState(() => _loading = true);
    try {
      await store.loadDepositAddresses();
      _pickDefault();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickDefault() {
    final nets = _networks(context.read<NovaStore>());
    if (nets.isEmpty) return;
    final enabled = nets.where((n) => n['deposits_enabled'] == true);
    setState(() => _networkId = (enabled.isNotEmpty ? enabled.first : nets.first)['network_id']);
  }

  List<Map<String, dynamic>> _networks(NovaStore s) =>
      s.depositAddresses.where((a) => a['asset'] == widget.symbol).toList();

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final credited = await context.read<NovaStore>().syncDeposits();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(credited.isEmpty
            ? 'No new confirmed deposits yet'
            : 'Received ${credited.join(', ')}'),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final scheme = Theme.of(context).colorScheme;
    final nets = _networks(store);
    final sel = nets.where((n) => n['network_id'] == _networkId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Receive ${widget.symbol}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    Text('Network', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: nets
                          .map((n) => ChoiceChip(
                                label: Text(n['network']),
                                selected: n['network_id'] == _networkId,
                                onSelected: (_) => setState(() => _networkId = n['network_id']),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    if (sel != null) ...[
                      if (sel['deposits_enabled'] != true)
                        NovaCard(
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.warning),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${widget.symbol} on ${sel['network']} has no official testnet token, so deposits '
                                'on this route are tracked from mainnet launch.',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ]),
                        )
                      else ...[
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: QrImageView(data: sel['address'], size: 200, backgroundColor: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 16),
                        NovaCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your ${widget.symbol} address (${sel['network']})',
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                              const SizedBox(height: 6),
                              SelectableText(sel['address'],
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: sel['address']));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(content: Text('Address copied')));
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 18),
                                    label: const Text('Copy'),
                                  ),
                                ),
                                if (sel['explorer'] != null) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => launchUrl(Uri.parse(sel['explorer']),
                                          mode: LaunchMode.externalApplication),
                                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                      label: const Text('Explorer'),
                                    ),
                                  ),
                                ],
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        NovaCard(
                          child: Column(children: [
                            DetailRow('Network', '${sel['network']} (testnet)'),
                            DetailRow('Confirmations needed', '${sel['confirmations']}'),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Only send ${widget.symbol} on ${sel['network']} to this address. '
                          'Other assets or networks may be lost.',
                          style: const TextStyle(color: AppColors.warning, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: _syncing ? null : _sync,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_syncing ? 'Checking blockchain...' : 'Check for deposits'),
                        ),
                      ],
                    ],
                  ],
                ),
    );
  }
}
