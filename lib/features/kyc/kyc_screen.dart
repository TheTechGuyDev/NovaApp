import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/widgets/nova_widgets.dart';

class KycScreen extends StatelessWidget {
  const KycScreen({super.key});

  static const _tiers = [
    (0, 'Starter', 'Account created', 50000.0),
    (1, 'Basic', 'Verify BVN', 200000.0),
    (2, 'Verified', 'Verify NIN', 5000000.0),
    (3, 'Premium', 'Selfie + address (coming soon)', 50000000.0),
  ];

  Future<void> _verify(BuildContext context, String type) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IdSheet(type: type),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.toUpperCase()} verified successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = context.watch<NovaStore>().profile?.kycLevel ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          NovaCard(
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.14),
                  ),
                  child: Icon(Icons.verified_user_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Level $level · ${_tiers[level].$2}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text('Daily limit ${formatMoney(_tiers[level].$4, symbol: '₦', decimals: 0)}',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ..._tiers.map((t) {
            final done = level >= t.$1;
            final next = t.$1 == level + 1;
            final type = t.$1 == 1 ? 'bvn' : (t.$1 == 2 ? 'nin' : null);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NovaCard(
                onTap: next && type != null ? () => _verify(context, type) : null,
                child: Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: done ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Level ${t.$1} · ${t.$2}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            '${t.$3} · up to ${formatMoney(t.$4, symbol: '₦', decimals: 0)}/day',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (next && type != null)
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(80, 38)),
                        onPressed: () => _verify(context, type),
                        child: const Text('Verify'),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          Text(
            'Sandbox test numbers: BVN 22222222222 · NIN 70123456789',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _IdSheet extends StatefulWidget {
  const _IdSheet({required this.type});
  final String type;

  @override
  State<_IdSheet> createState() => _IdSheetState();
}

class _IdSheetState extends State<_IdSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<NovaStore>().verifyKyc(widget.type, _ctrl.text.trim());
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.type.toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Verify your $label',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            widget.type == 'bvn'
                ? 'Dial *565*0# on your registered line to get your BVN.'
                : 'Dial *346# on your registered line to get your NIN.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: '11-digit $label', errorText: _error),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _ctrl.text.length == 11 && !_busy ? _submit : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Verify $label'),
          ),
        ],
      ),
    );
  }
}
