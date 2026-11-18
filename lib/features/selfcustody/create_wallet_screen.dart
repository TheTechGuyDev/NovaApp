import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';
import 'self_custody.dart';
import 'wallet_detail_screen.dart';

/// Create: warnings -> show phrase -> verify 3 words -> name -> save.
class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key});
  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  int _step = 0;
  final _accepted = [false, false, false];
  late final String _phrase = SelfCustodyStore.generatePhrase();
  late final List<String> _words = _phrase.split(' ');
  late final List<int> _check = (List.generate(_words.length, (i) => i)..shuffle(Random.secure())).take(3).toList()
    ..sort();
  final Map<int, String> _answers = {};
  final _label = TextEditingController(text: 'My Wallet');
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final w = await context
          .read<SelfCustodyStore>()
          .addFromPhrase(_phrase, label: _label.text, source: 'created');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WalletDetailScreen(wallet: w)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Create wallet · ${_step + 1}/3')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: switch (_step) {
          0 => [
              const Text('Before you start', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('You are about to see a 12-word recovery phrase. It is the only way to restore this wallet.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              for (final (i, t) in [
                'If I lose my recovery phrase, my funds are lost forever.',
                'NOVA cannot recover my phrase or reverse my transactions.',
                'I will never share my phrase with anyone, including NOVA staff.',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NovaCard(
                    onTap: () => setState(() => _accepted[i] = !_accepted[i]),
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(_accepted[i] ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t, style: const TextStyle(fontSize: 14))),
                    ]),
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _accepted.every((a) => a) ? () => setState(() => _step = 1) : null,
                child: const Text('Show my recovery phrase'),
              ),
            ],
          1 => [
              const Text('Write these words down', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('In this exact order, on paper. Do not screenshot or store it online.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              PhraseGrid(words: _words),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _phrase));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied. Clear your clipboard after saving it safely.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy (not recommended)'),
              ),
              const SizedBox(height: 10),
              FilledButton(onPressed: () => setState(() => _step = 2), child: const Text("I've written it down")),
            ],
          _ => [
              const Text('Confirm your phrase', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Type the requested words to prove you saved it.', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              for (final i in _check)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    autocorrect: false,
                    onChanged: (v) => setState(() => _answers[i] = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      labelText: 'Word #${i + 1}',
                      suffixIcon: _answers[i] == _words[i]
                          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                          : null,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              TextField(controller: _label, decoration: const InputDecoration(labelText: 'Wallet name')),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _check.every((i) => _answers[i] == _words[i]) && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create wallet'),
              ),
              TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Show phrase again')),
            ],
        },
      ),
    );
  }
}

class PhraseGrid extends StatelessWidget {
  const PhraseGrid({super.key, required this.words});
  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: [
        for (final (i, w) in words.indexed)
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outline),
            ),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${i + 1}. ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              TextSpan(text: w, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ])),
          ),
      ],
    );
  }
}

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});
  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _phrase = TextEditingController();
  final _label = TextEditingController(text: 'Imported Wallet');
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final w = await context
          .read<SelfCustodyStore>()
          .addFromPhrase(_phrase.text, label: _label.text, source: 'imported');
      _phrase.clear();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WalletDetailScreen(wallet: w)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = SelfCustodyStore.isValidPhrase(_phrase.text);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Import wallet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('Enter a 12 or 24-word recovery phrase from MetaMask, Trust Wallet, Phantom or another NOVA device.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          TextField(
            controller: _phrase,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Recovery phrase',
              alignLabelWithHint: true,
              errorText: _phrase.text.trim().split(RegExp(r'\s+')).length >= 12 && !valid
                  ? 'Invalid phrase. Check spelling and word order.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Wallet name')),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.success),
            SizedBox(width: 6),
            Expanded(
              child: Text('Your phrase is encrypted on this device and never sent to NOVA.',
                  style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: valid && !_busy ? _import : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Import'),
          ),
        ],
      ),
    );
  }
}
