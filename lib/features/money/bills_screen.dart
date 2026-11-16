import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/widgets/nova_widgets.dart';
import 'money_widgets.dart';

class _Category {
  const _Category(this.id, this.label, this.icon, this.billers, this.customerLabel, this.customerLength);
  final String id;
  final String label;
  final IconData icon;
  final List<String> billers;
  final String customerLabel;
  final int customerLength;
}

const _categories = [
  _Category('airtime', 'Airtime', Icons.phone_android_rounded, ['MTN', 'Airtel', 'Glo', '9mobile'], 'Phone number', 11),
  _Category('data', 'Data', Icons.wifi_rounded, ['MTN', 'Airtel', 'Glo', '9mobile'], 'Phone number', 11),
  _Category('electricity', 'Electricity', Icons.bolt_rounded,
      ['Ikeja Electric', 'Eko Electric', 'Abuja Electric', 'Ibadan Electric'], 'Meter number', 11),
  _Category('cable', 'Cable TV', Icons.tv_rounded, ['DStv', 'GOtv', 'Startimes'], 'Smartcard / IUC number', 10),
];

const _dataPlans = [
  ('1GB · 1 day', 350.0),
  ('2GB · 7 days', 1000.0),
  ('5GB · 30 days', 2500.0),
  ('12GB · 30 days', 5000.0),
];

const _cablePlans = [
  ('Basic', 3600.0),
  ('Compact', 12500.0),
  ('Compact Plus', 19800.0),
  ('Premium', 37000.0),
];

class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pay Bills')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: _categories
                .map((c) => NovaCard(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => _BillForm(category: c))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                            child: Icon(c.icon, color: scheme.primary),
                          ),
                          Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Text('Bills are simulated in the sandbox preview. A live bills provider connects before launch.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _BillForm extends StatefulWidget {
  const _BillForm({required this.category});
  final _Category category;
  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  late String _biller = widget.category.billers.first;
  final _customer = TextEditingController();
  final _amt = TextEditingController();
  String? _plan;
  bool _busy = false;
  final _key = newIdempotencyKey();

  List<(String, double)>? get _plans => switch (widget.category.id) {
        'data' => _dataPlans,
        'cable' => _cablePlans,
        _ => null,
      };

  double get _amount => double.tryParse(_amt.text) ?? 0;

  Future<void> _pay() async {
    final store = context.read<NovaStore>();
    final c = widget.category;
    final pin = await askPin(context,
        title: 'Confirm payment',
        subtitle: '${formatMoney(_amount, symbol: '₦')} $_biller ${c.label}\nfor ${_customer.text}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await store.banking('pay_bill', {
        'category': c.id,
        'biller': _biller,
        'customer': _customer.text,
        'amount': _amount,
        'plan': _plan,
        'pin': pin,
        'idempotency_key': _key,
      });
      await store.refreshMoney();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          title: '$_biller ${c.label} paid',
          amount: formatMoney(_amount, symbol: '₦'),
          highlight: r['token'] != null ? ('Electricity token', '${r['token']}') : null,
          rows: [
            (c.customerLabel, _customer.text),
            if (_plan != null) ('Plan', _plan!),
            ('Reference', '${r['reference']}'),
            if (r['simulated'] == true) ('Mode', 'Sandbox simulation'),
          ],
        ),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final scheme = Theme.of(context).colorScheme;
    final ok = _customer.text.length == c.customerLength && _amount >= 50 && !_busy;
    final bal = context.watch<NovaStore>().holding('NGN')?.balance ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(c.label)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Provider', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: c.billers
                .map((b) => ChoiceChip(
                      label: Text(b),
                      selected: _biller == b,
                      onSelected: (_) => setState(() => _biller = b),
                    ))
                .toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _customer,
            keyboardType: TextInputType.number,
            maxLength: c.customerLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: c.customerLabel),
          ),
          if (_plans != null) ...[
            const SizedBox(height: 6),
            Text('Plan', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ..._plans!.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NovaCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () => setState(() {
                      _plan = p.$1;
                      _amt.text = p.$2.toStringAsFixed(0);
                    }),
                    child: Row(children: [
                      Icon(_plan == p.$1 ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: scheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.$1)),
                      Text(formatMoney(p.$2, symbol: '₦', decimals: 0),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                )),
          ] else ...[
            const SizedBox(height: 6),
            AmountField(controller: _amt, onChanged: (_) => setState(() {}), helper: 'Minimum ₦50'),
          ],
          const SizedBox(height: 8),
          Text('Balance: ${formatMoney(bal, symbol: '₦')}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: ok ? _pay : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_amount > 0 ? 'Pay ${formatMoney(_amount, symbol: '₦')}' : 'Pay'),
          ),
        ],
      ),
    );
  }
}
