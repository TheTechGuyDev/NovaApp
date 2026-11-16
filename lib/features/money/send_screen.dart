import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/widgets/nova_widgets.dart';
import 'money_widgets.dart';

class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Send Money'),
          bottom: const TabBar(tabs: [Tab(text: 'NOVA User'), Tab(text: 'Bank Account')]),
        ),
        body: const TabBarView(children: [_SendNova(), _SendBank()]),
      ),
    );
  }
}

double _amount(TextEditingController c) => double.tryParse(c.text) ?? 0;

class _BalanceHint extends StatelessWidget {
  const _BalanceHint();
  @override
  Widget build(BuildContext context) {
    final bal = context.watch<NovaStore>().holding('NGN')?.balance ?? 0;
    return Text('Balance: ${formatMoney(bal, symbol: '₦')}',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13));
  }
}

// --------------------------------------------------------------- NOVA user
class _SendNova extends StatefulWidget {
  const _SendNova();
  @override
  State<_SendNova> createState() => _SendNovaState();
}

class _SendNovaState extends State<_SendNova> {
  final _user = TextEditingController();
  final _amt = TextEditingController();
  final _note = TextEditingController();
  Timer? _debounce;
  Map<String, String>? _recipient;
  bool _looking = false;
  bool _busy = false;
  final _key = newIdempotencyKey();

  void _lookup(String v) {
    _debounce?.cancel();
    setState(() => _recipient = null);
    final u = v.trim().replaceFirst('@', '').toLowerCase();
    if (u.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _looking = true);
      final r = await context.read<NovaStore>().lookupUser(u);
      if (!mounted) return;
      setState(() {
        _looking = false;
        if (_user.text.trim().replaceFirst('@', '').toLowerCase() == u) _recipient = r;
      });
    });
  }

  Future<void> _send() async {
    final store = context.read<NovaStore>();
    final amount = _amount(_amt);
    final pin = await askPin(context,
        title: 'Confirm transfer',
        subtitle: 'Send ${formatMoney(amount, symbol: '₦')} to ${_recipient!['full_name']}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await store.banking('send_nova', {
        'username': _recipient!['username'],
        'amount': amount,
        'pin': pin,
        'note': _note.text.trim(),
        'idempotency_key': _key,
      });
      await store.refreshMoney();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          title: 'Sent to ${_recipient!['full_name']}',
          amount: formatMoney(amount, symbol: '₦'),
          rows: [
            ('Recipient', '@${_recipient!['username']}'),
            ('Fee', '₦0.00'),
            ('Reference', '${r['reference']}'),
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
    final scheme = Theme.of(context).colorScheme;
    final me = context.watch<NovaStore>().profile?.username;
    final ok = _recipient != null && _recipient!['username'] != me && _amount(_amt) >= 1 && !_busy;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _user,
          onChanged: _lookup,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'NOVA username',
            prefixText: '@ ',
            suffixIcon: _looking
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
        ),
        const SizedBox(height: 10),
        if (_recipient != null)
          NovaCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.verified_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _recipient!['username'] == me ? "That's you" : _recipient!['full_name']!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          )
        else if (_user.text.trim().length >= 3 && !_looking)
          Text('No NOVA user with that username', style: TextStyle(color: scheme.error, fontSize: 13)),
        const SizedBox(height: 18),
        AmountField(controller: _amt, onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        const _BalanceHint(),
        const SizedBox(height: 14),
        TextField(controller: _note, maxLength: 80, decoration: const InputDecoration(labelText: 'Note (optional)')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: ok ? _send : null,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send · Free'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- Bank
class _SendBank extends StatefulWidget {
  const _SendBank();
  @override
  State<_SendBank> createState() => _SendBankState();
}

class _SendBankState extends State<_SendBank> {
  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _bank;
  final _acct = TextEditingController();
  final _amt = TextEditingController();
  final _note = TextEditingController();
  String? _acctName;
  bool _resolving = false;
  bool _busy = false;
  final _key = newIdempotencyKey();

  double get _fee {
    final a = _amount(_amt);
    if (a <= 0) return 0;
    return a <= 5000 ? 10 : (a <= 50000 ? 25 : 50);
  }

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final r = await context.read<NovaStore>().banking('banks');
      if (mounted) {
        setState(() => _banks = List<Map<String, dynamic>>.from(r['banks'] as List));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _resolve() async {
    if (_bank == null || _acct.text.length != 10) return;
    setState(() {
      _resolving = true;
      _acctName = null;
    });
    try {
      final r = await context.read<NovaStore>().banking('resolve', {
        'account_number': _acct.text,
        'bank_code': _bank!['code'],
      });
      if (mounted) setState(() => _acctName = r['account_name']);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _pickBank() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BankPicker(banks: _banks),
    );
    if (picked != null) {
      setState(() => _bank = picked);
      _resolve();
    }
  }

  Future<void> _send() async {
    final store = context.read<NovaStore>();
    final amount = _amount(_amt);
    final pin = await askPin(context,
        title: 'Confirm transfer',
        subtitle: 'Send ${formatMoney(amount, symbol: '₦')} to $_acctName\n'
            'Fee ${formatMoney(_fee, symbol: '₦')}');
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await store.banking('send_bank', {
        'amount': amount,
        'pin': pin,
        'bank_code': _bank!['code'],
        'bank_name': _bank!['name'],
        'account_number': _acct.text,
        'account_name': _acctName,
        'note': _note.text.trim(),
        'idempotency_key': _key,
      });
      await store.refreshMoney();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          title: 'Sent to $_acctName',
          amount: formatMoney(amount, symbol: '₦'),
          rows: [
            ('Bank', '${_bank!['name']}'),
            ('Account', _acct.text),
            ('Fee', formatMoney((r['fee'] as num).toDouble(), symbol: '₦')),
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
    final scheme = Theme.of(context).colorScheme;
    final ok = _acctName != null && _amount(_amt) >= 100 && !_busy;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        InkWell(
          onTap: _banks.isEmpty ? null : _pickBank,
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Bank',
              prefixIcon: Icon(Icons.account_balance_outlined),
              suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
            ),
            child: Text(_bank?['name'] ?? (_banks.isEmpty ? 'Loading banks...' : 'Select bank')),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _acct,
          keyboardType: TextInputType.number,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            setState(() => _acctName = null);
            if (v.length == 10) _resolve();
          },
          decoration: const InputDecoration(labelText: 'Account number', prefixIcon: Icon(Icons.numbers_rounded)),
        ),
        if (_resolving) const LinearProgressIndicator(),
        if (_acctName != null)
          NovaCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.verified_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(_acctName!, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        const SizedBox(height: 18),
        AmountField(
          controller: _amt,
          onChanged: (_) => setState(() {}),
          helper: _fee > 0 ? 'Fee ${formatMoney(_fee, symbol: '₦')}' : 'Minimum ₦100',
        ),
        const SizedBox(height: 6),
        const _BalanceHint(),
        const SizedBox(height: 14),
        TextField(controller: _note, maxLength: 80, decoration: const InputDecoration(labelText: 'Narration (optional)')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: ok ? _send : null,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue'),
        ),
      ],
    );
  }
}

class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.banks});
  final List<Map<String, dynamic>> banks;
  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.banks
        .where((b) => (b['name'] as String).toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Search bank', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(list[i]['name']),
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
