import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/widgets/nova_widgets.dart';
import '../kyc/kyc_screen.dart';
import 'money_widgets.dart';

/// Receive / add money: dedicated account number, @username, card checkout
/// and (sandbox only) an instant test top-up.
class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});
  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  bool _creating = false;
  String? _pendingRef;
  bool _verifying = false;

  Future<void> _createAccount() async {
    setState(() => _creating = true);
    try {
      await context.read<NovaStore>().createVirtualAccount();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<double?> _askAmount(String title, {double min = 100}) {
    final c = TextEditingController();
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(
          builder: (ctx, set) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              AmountField(controller: c, onChanged: (_) => set(() {}), helper: 'Minimum ${formatMoney(min, symbol: '₦', decimals: 0)}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [1000, 5000, 20000, 100000]
                    .map((v) => ActionChip(
                          label: Text(formatMoney(v.toDouble(), symbol: '₦', decimals: 0)),
                          onPressed: () => set(() => c.text = '$v'),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (double.tryParse(c.text) ?? 0) >= min
                    ? () => Navigator.pop(ctx, double.parse(c.text))
                    : null,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _payWithPaystack() async {
    final store = context.read<NovaStore>();
    final amount = await _askAmount('Fund with card or bank');
    if (amount == null || !mounted) return;
    try {
      final r = await store.banking('fund_init', {'amount': amount});
      setState(() => _pendingRef = r['reference']);
      await launchUrl(Uri.parse(r['authorization_url']), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _verify() async {
    final store = context.read<NovaStore>();
    setState(() => _verifying = true);
    try {
      final r = await store.banking('fund_verify', {'reference': _pendingRef});
      await store.refreshMoney();
      if (!mounted) return;
      if (r['status'] == 'completed') {
        setState(() => _pendingRef = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Payment confirmed. Wallet funded.')));
      } else {
        showError(context, 'Payment is ${r['status']}. Complete checkout, then try again.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _testTopUp() async {
    final store = context.read<NovaStore>();
    final amount = await _askAmount('Sandbox test top-up');
    if (amount == null || !mounted) return;
    try {
      await store.banking('fund_test', {'amount': amount});
      await store.refreshMoney();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${formatMoney(amount, symbol: '₦')} test funds added')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final va = store.virtualAccount;
    final profile = store.profile!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Money')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('Bank transfer', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          NovaCard(
            child: va != null
                ? Column(children: [
                    DetailRow('Bank', '${va['bank_name']}'),
                    DetailRow('Account number', '${va['account_number']}', copy: true),
                    DetailRow('Account name', '${va['account_name']}'),
                    if (va['provider'] == 'sandbox')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Preview account. Live accounts are issued once Paystack approves NOVA.',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      ),
                  ])
                : profile.kycLevel < 1
                    ? ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.lock_outline_rounded, color: scheme.primary),
                        title: const Text('Verify BVN to get your account number'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const KycScreen())),
                      )
                    : FilledButton.icon(
                        onPressed: _creating ? null : _createAccount,
                        icon: const Icon(Icons.account_balance_rounded),
                        label: Text(_creating ? 'Creating...' : 'Get my account number'),
                      ),
          ),
          const SizedBox(height: 20),
          Text('Other ways', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _Option(
            icon: Icons.credit_card_rounded,
            title: 'Card, bank or USSD',
            subtitle: 'Secure Paystack checkout',
            onTap: _payWithPaystack,
          ),
          if (_pendingRef != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.tonal(
                onPressed: _verifying ? null : _verify,
                child: Text(_verifying ? 'Checking...' : "I've completed payment"),
              ),
            ),
          _Option(
            icon: Icons.alternate_email_rounded,
            title: 'Share your NOVA tag',
            subtitle: 'Receive free from @${profile.username}',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Your tag is @${profile.username}')),
            ),
          ),
          if (AppConfig.environment == 'sandbox')
            _Option(
              icon: Icons.science_outlined,
              title: 'Sandbox test top-up',
              subtitle: 'Instantly add test Naira (preview only)',
              onTap: _testTopUp,
            ),
          const SizedBox(height: 8),
          Text('Paystack test card: 4084 0840 8408 4081 · any future date · CVV 408 · PIN 0000 · OTP 123456',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NovaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: scheme.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}
