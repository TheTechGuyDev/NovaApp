import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../../core/widgets/pin_pad.dart';

/// Asks for the transaction PIN. Returns the PIN, or null if dismissed.
Future<String?> askPin(BuildContext context, {required String title, String? subtitle}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 24),
            PinPad(onCompleted: (pin) => Navigator.pop(ctx, pin)),
          ],
        ),
      ),
    ),
  );
}

/// Full-screen success / receipt view after a money movement.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({
    super.key,
    required this.title,
    required this.amount,
    required this.rows,
    this.highlight,
  });

  final String title;
  final String amount;
  final List<(String, String)> rows;
  final (String, String)? highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [AppColors.neon, AppColors.primaryDeep]),
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
                  ),
                ),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
                const SizedBox(height: 6),
                Text(amount,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                if (highlight != null) ...[
                  NovaCard(
                    child: Column(
                      children: [
                        Text(highlight!.$1, style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        SelectableText(highlight!.$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                NovaCard(child: Column(children: rows.map((r) => DetailRow(r.$1, r.$2)).toList())),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.copy = false});
  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          if (copy)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_rounded, size: 16, color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

void showTxnDetails(BuildContext context, TxnItem t) {
  final cp = t.counterparty;
  final rows = <(String, String)>[
    ('Status', t.status[0].toUpperCase() + t.status.substring(1)),
    ('Date', friendlyDate(t.createdAt)),
    ('Reference', t.reference),
    if (t.fee > 0) ('Fee', t.asset == 'NGN' ? formatMoney(t.fee, symbol: '₦') : '${formatCrypto(t.fee)} ${t.asset}'),
    if (cp['kind'] == 'bank') ...[
      ('Bank', '${cp['bank_name'] ?? ''}'),
      ('Account', '${cp['account_number']} · ${cp['account_name']}'),
    ],
    if (cp['kind'] == 'nova_user') ('NOVA user', '@${cp['username']} · ${cp['name'] ?? ''}'),
    if (cp['kind'] == 'biller') ...[
      ('Biller', '${cp['biller']}'),
      ('Customer', '${cp['customer']}'),
    ],
    if (cp['kind'] == 'crypto' && cp['address'] != null) ('Address', '${cp['address']}'),
    if (t.networkId != null) ('Network', t.networkId!.replaceAll('_', ' · ')),
    if (t.txHash != null && !t.txHash!.startsWith('bal-')) ('Tx hash', t.txHash!),
    if (t.metadata['token'] != null) ('Token', '${t.metadata['token']}'),
    if (t.metadata['note'] != null) ('Note', '${t.metadata['note']}'),
    if (t.metadata['simulated'] == true) ('Mode', 'Sandbox simulation'),
  ];
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, color: Theme.of(ctx).colorScheme.primary, size: 30),
            const SizedBox(height: 8),
            Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Text(t.amountLabel,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: t.incoming ? AppColors.success : null)),
            const SizedBox(height: 16),
            ...rows.map((r) => DetailRow(r.$1, r.$2, copy: const ['Reference', 'Token', 'Tx hash', 'Address'].contains(r.$1))),
          ],
        ),
      ),
    ),
  );
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('$e'),
    backgroundColor: AppColors.danger,
  ));
}

/// Big centred amount input used by send/fund/bills.
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.onChanged, this.helper});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixText: '₦ ',
        helperText: helper,
      ),
    );
  }
}

String newIdempotencyKey() =>
    '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().hashCode}';
