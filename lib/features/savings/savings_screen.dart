import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';

const _icons = {
  'savings': Icons.savings_rounded,
  'laptop': Icons.laptop_mac_rounded,
  'home': Icons.home_rounded,
  'car': Icons.directions_car_rounded,
  'travel': Icons.flight_rounded,
  'school': Icons.school_rounded,
  'health': Icons.favorite_rounded,
  'gift': Icons.card_giftcard_rounded,
};

IconData planIcon(SavingsPlan p) =>
    _icons[p.icon] ?? (p.kind == 'fixed' ? Icons.lock_rounded : p.kind == 'goal' ? Icons.flag_rounded : Icons.savings_rounded);

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});
  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<NovaStore>().loadSavings().catchError((e) {
      if (mounted) showError(context, e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);
    final active = store.savings.where((p) => p.active).toList();
    final closed = store.savings.where((p) => !p.active).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Savings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreatePlanScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New plan'),
      ),
      body: RefreshIndicator(
        onRefresh: store.loadSavings,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total savings', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(formatMoney(store.totalSaved, symbol: '₦'),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(children: [
                  const Icon(Icons.trending_up_rounded, color: AppColors.neon, size: 18),
                  const SizedBox(width: 6),
                  Text('${formatMoney(store.totalInterest, symbol: '₦')} interest earned',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            const _RatesStrip(),
            const SizedBox(height: 20),
            if (active.isEmpty)
              NovaCard(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Column(children: [
                  Icon(Icons.savings_outlined, size: 36, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text('Start your first savings plan', style: TextStyle(color: scheme.onSurfaceVariant)),
                ]),
              )
            else ...[
              const Text('Active plans', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 10),
              ...active.map((p) => _PlanTile(plan: p)),
            ],
            if (closed.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Closed', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              ...closed.map((p) => _PlanTile(plan: p)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatesStrip extends StatelessWidget {
  const _RatesStrip();
  @override
  Widget build(BuildContext context) {
    const items = [('Flexible', '10%'), ('Goal', '12%'), ('Fixed', 'up to 20%')];
    return Row(
      children: items
          .map((e) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: NovaCard(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(children: [
                      Text(e.$2,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      Text('${e.$1} p.a.', style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan});
  final SavingsPlan plan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = plan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NovaCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanDetailScreen(planId: p.id))),
        child: Column(children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(planIcon(p), color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${p.kindLabel} · ${p.rate.toStringAsFixed(0)}% p.a.'
                  '${p.isLocked ? ' · until ${friendlyDate(p.lockedUntil!).split(',').first}' : ''}'
                  '${p.active ? '' : ' · closed'}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(p.balance, symbol: '₦'), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (p.interestEarned > 0)
                Text('+${formatMoney(p.interestEarned, symbol: '₦')}',
                    style: const TextStyle(color: AppColors.success, fontSize: 12)),
            ]),
          ]),
          if (p.kind == 'goal' && p.target != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: p.progress, minHeight: 8),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${(p.progress * 100).toStringAsFixed(0)}% of ${formatMoney(p.target!, symbol: '₦', decimals: 0)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- create
class CreatePlanScreen extends StatefulWidget {
  const CreatePlanScreen({super.key});
  @override
  State<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends State<CreatePlanScreen> {
  String _kind = 'flexible';
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _auto = TextEditingController();
  int _lockDays = 90;
  String? _freq;
  String _icon = 'savings';
  bool _busy = false;

  static const _fixedRates = {30: 14, 90: 16, 180: 18, 365: 20};

  Future<void> _create() async {
    final store = context.read<NovaStore>();
    setState(() => _busy = true);
    try {
      final id = await store.rpc('savings_create', {
        '_kind': _kind,
        '_name': _name.text,
        '_target': _kind == 'goal' ? double.tryParse(_target.text) : null,
        '_lock_days': _kind == 'fixed' ? _lockDays : null,
        '_auto_amount': _freq != null ? double.tryParse(_auto.text) : null,
        '_auto_frequency': _kind == 'fixed' ? null : _freq,
        '_icon': _icon,
      });
      await store.loadSavings();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PlanDetailScreen(planId: id, depositNow: true)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = switch (_kind) { 'flexible' => 10, 'goal' => 12, _ => _fixedRates[_lockDays]! };
    final ok = _name.text.trim().isNotEmpty &&
        (_kind != 'goal' || (double.tryParse(_target.text) ?? 0) > 0) &&
        (_freq == null || (double.tryParse(_auto.text) ?? 0) >= 100) &&
        !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('New savings plan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'flexible', label: Text('Flexible'), icon: Icon(Icons.savings_rounded)),
              ButtonSegment(value: 'goal', label: Text('Goal'), icon: Icon(Icons.flag_rounded)),
              ButtonSegment(value: 'fixed', label: Text('Fixed'), icon: Icon(Icons.lock_rounded)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          Text(
            switch (_kind) {
              'flexible' => 'Save and withdraw anytime. Interest is added daily.',
              'goal' => 'Save towards a target with optional automatic deposits.',
              _ => 'Lock money for a fixed period for the highest rate. Breaking early forfeits interest.',
            },
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Plan name', hintText: 'e.g. Rent, New phone'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _icons.entries
                .map((e) => ChoiceChip(
                      label: Icon(e.value, size: 18),
                      selected: _icon == e.key,
                      onSelected: (_) => setState(() => _icon = e.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          if (_kind == 'goal')
            AmountField(controller: _target, onChanged: (_) => setState(() {}), helper: 'Target amount'),
          if (_kind == 'fixed') ...[
            Text('Lock period', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _fixedRates.entries
                  .map((e) => ChoiceChip(
                        label: Text('${e.key} days · ${e.value}%'),
                        selected: _lockDays == e.key,
                        onSelected: (_) => setState(() => _lockDays = e.key),
                      ))
                  .toList(),
            ),
          ],
          if (_kind != 'fixed') ...[
            const SizedBox(height: 16),
            Text('Auto-save (optional)', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final f in [null, 'daily', 'weekly', 'monthly'])
                ChoiceChip(
                  label: Text(f == null ? 'Off' : f[0].toUpperCase() + f.substring(1)),
                  selected: _freq == f,
                  onSelected: (_) => setState(() => _freq = f),
                ),
            ]),
            if (_freq != null) ...[
              const SizedBox(height: 10),
              AmountField(controller: _auto, onChanged: (_) => setState(() {}), helper: 'Amount per $_freq save'),
            ],
          ],
          const SizedBox(height: 18),
          NovaCard(
            child: Row(children: [
              Icon(Icons.trending_up_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Text('$rate% per year', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('₦100,000 earns ≈ ${formatMoney(100000 * rate / 100, symbol: '₦', decimals: 0)}/yr',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: ok ? _create : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create plan'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- detail
class PlanDetailScreen extends StatefulWidget {
  const PlanDetailScreen({super.key, required this.planId, this.depositNow = false});
  final String planId;
  final bool depositNow;
  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.depositNow) WidgetsBinding.instance.addPostFrameCallback((_) => _move(deposit: true));
  }

  Future<void> _move({required bool deposit}) async {
    final store = context.read<NovaStore>();
    final p = store.savings.firstWhere((x) => x.id == widget.planId);
    final c = TextEditingController(text: !deposit && p.kind == 'fixed' ? p.balance.toStringAsFixed(2) : '');
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, set) {
          final v = double.tryParse(c.text) ?? 0;
          final max = deposit ? store.holding('NGN')!.balance : p.balance;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(deposit ? 'Add to ${p.name}' : (p.isLocked ? 'Break ${p.name} early' : 'Withdraw from ${p.name}'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            AmountField(
              controller: c,
              onChanged: (_) => set(() {}),
              helper: '${deposit ? 'Naira balance' : 'Plan balance'}: ${formatMoney(max, symbol: '₦')}',
            ),
            if (!deposit && p.isLocked)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'This plan is locked until ${friendlyDate(p.lockedUntil!).split(',').first}. '
                  'Breaking now returns your principal and forfeits ${formatMoney(p.interestEarned, symbol: '₦')} interest.',
                  style: const TextStyle(color: AppColors.warning, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (deposit ? v >= 100 : v > 0) && v <= max + 0.001 ? () => Navigator.pop(ctx, v) : null,
              child: Text(deposit ? 'Save' : (p.isLocked ? 'Break plan' : 'Withdraw')),
            ),
          ]);
        }),
      ),
    );
    if (amount == null || !mounted) return;
    final pin = await askPin(context, title: deposit ? 'Confirm savings' : 'Confirm withdrawal');
    if (pin == null || !mounted) return;
    try {
      final key = newIdempotencyKey();
      if (deposit) {
        await store.rpc('savings_deposit', {'_plan': p.id, '_amount': amount, '_pin': pin, '_key': key});
      } else {
        await store.rpc('savings_withdraw', {
          '_plan': p.id,
          '_amount': p.kind == 'fixed' ? null : amount,
          '_pin': pin,
          '_key': key,
        });
      }
      await Future.wait([store.loadSavings(), store.refreshMoney()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(deposit ? 'Saved ${formatMoney(amount, symbol: '₦')}' : 'Moved to your Naira wallet'),
        ));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editAuto(SavingsPlan p) async {
    final store = context.read<NovaStore>();
    String? freq = p.autoFrequency;
    final c = TextEditingController(text: p.autoAmount?.toStringAsFixed(0) ?? '');
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, set) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Auto-save', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final f in [null, 'daily', 'weekly', 'monthly'])
                ChoiceChip(
                  label: Text(f == null ? 'Off' : f[0].toUpperCase() + f.substring(1)),
                  selected: freq == f,
                  onSelected: (_) => set(() => freq = f),
                ),
            ]),
            if (freq != null) ...[
              const SizedBox(height: 12),
              AmountField(controller: c, onChanged: (_) => set(() {})),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ]);
        }),
      ),
    );
    if (save != true) return;
    try {
      await store.rpc('savings_update_auto', {
        '_plan': p.id,
        '_amount': double.tryParse(c.text),
        '_frequency': freq,
      });
      await store.loadSavings();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NovaStore>();
    final p = store.savings.where((x) => x.id == widget.planId).firstOrNull;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);
    final history = store.transactions.where((t) => t.metadata['plan_id'] == p.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(planIcon(p), color: Colors.white),
                const SizedBox(width: 8),
                Text('${p.kindLabel} · ${p.rate.toStringAsFixed(0)}% p.a.',
                    style: const TextStyle(color: Colors.white70)),
              ]),
              const SizedBox(height: 14),
              Text(formatMoney(p.balance, symbol: '₦'),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${formatMoney(p.interestEarned, symbol: '₦')} interest earned',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              if (p.kind == 'goal' && p.target != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: p.progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    color: AppColors.neon,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${(p.progress * 100).toStringAsFixed(0)}% of ${formatMoney(p.target!, symbol: '₦', decimals: 0)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          if (p.active)
            Row(children: [
              if (!(p.kind == 'fixed' && p.principal > 0))
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _move(deposit: true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Save'),
                  ),
                ),
              if (!(p.kind == 'fixed' && p.principal > 0)) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: p.balance > 0 ? () => _move(deposit: false) : null,
                  icon: Icon(p.isLocked ? Icons.lock_open_rounded : Icons.north_east_rounded),
                  label: Text(p.isLocked ? 'Break early' : 'Withdraw'),
                ),
              ),
            ]),
          const SizedBox(height: 16),
          NovaCard(
            child: Column(children: [
              DetailRow('Principal', formatMoney(p.principal, symbol: '₦')),
              DetailRow('Interest rate', '${p.rate.toStringAsFixed(1)}% per year, added daily'),
              if (p.lockedUntil != null) DetailRow('Unlocks', friendlyDate(p.lockedUntil!).split(',').first),
              if (p.kind != 'fixed')
                InkWell(
                  onTap: p.active ? () => _editAuto(p) : null,
                  child: DetailRow(
                    'Auto-save',
                    p.autoFrequency == null
                        ? 'Off · tap to set'
                        : '${formatMoney(p.autoAmount!, symbol: '₦', decimals: 0)} ${p.autoFrequency}',
                  ),
                ),
              DetailRow('Status', p.status[0].toUpperCase() + p.status.substring(1)),
            ]),
          ),
          const SizedBox(height: 18),
          const Text('Activity', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 10),
          if (history.isEmpty)
            Text('No activity yet', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            ...history.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NovaCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(friendlyDate(t.createdAt), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                        ]),
                      ),
                      Text(
                        formatMoney(t.amount.abs(), symbol: '₦'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: t.type == 'savings_withdrawal' ? null : AppColors.success,
                        ),
                      ),
                    ]),
                  ),
                )),
        ],
      ),
    );
  }
}
