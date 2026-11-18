import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../money/money_widgets.dart';

const _catColors = {
  'Shopping': Color(0xFF8B5CF6),
  'Groceries': Color(0xFF22C55E),
  'Food & Drinks': Color(0xFFF97316),
  'Entertainment': Color(0xFFEC4899),
  'Subscriptions': Color(0xFF06B6D4),
  'Transport': Color(0xFFEAB308),
  'Utilities': Color(0xFF3B82F6),
  'Airtime & Data': Color(0xFF14B8A6),
  'Transfers': Color(0xFF94A3B8),
  'Bills': Color(0xFF6366F1),
  'Fees & Cards': Color(0xFFF43F5E),
  'Other': Color(0xFF64748B),
};

const budgetCategories = [
  'Shopping', 'Groceries', 'Food & Drinks', 'Entertainment', 'Subscriptions',
  'Transport', 'Utilities', 'Airtime & Data', 'Transfers',
];

Color catColor(String c) => _catColors[c] ?? const Color(0xFF64748B);

/// Monthly spending insights: cash flow, category breakdown and budgets.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<(String, double, int)> _cats = [];
  (double, double, double) _flow = (0, 0, 0);
  List<Map<String, dynamic>> _budgets = [];
  bool _loading = true;
  int? _touched;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _monthArg => '${_month.year}-${_month.month.toString().padLeft(2, '0')}-01';

  Future<void> _load() async {
    final store = context.read<NovaStore>();
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        store.rpc('spending_summary', {'_month': _monthArg}),
        store.rpc('cashflow_summary', {'_month': _monthArg}),
        sb.from('budgets').select().order('category'),
      ]);
      _cats = (res[0] as List)
          .map((r) => (r['category'] as String? ?? 'Other', asDouble(r['total']), (r['count'] as num).toInt()))
          .toList();
      final f = (res[1] as List).first;
      _flow = (asDouble(f['money_in']), asDouble(f['money_out']), asDouble(f['saved']));
      _budgets = List<Map<String, dynamic>>.from(res[2] as List);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int m) {
    final next = DateTime(_month.year, _month.month + m);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _month = next);
    _load();
  }

  Future<void> _editBudget([Map<String, dynamic>? existing]) async {
    String cat = existing?['category'] ?? budgetCategories.first;
    final ctrl = TextEditingController(text: existing == null ? '' : asDouble(existing['monthly_limit']).toStringAsFixed(0));
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, set) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(existing == null ? 'New budget' : 'Edit ${existing['category']} budget',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            if (existing == null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: budgetCategories
                    .where((c) => !_budgets.any((b) => b['category'] == c))
                    .map((c) => ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => set(() => cat = c)))
                    .toList(),
              ),
            const SizedBox(height: 14),
            AmountField(controller: ctrl, onChanged: (_) => set(() {}), helper: 'Monthly limit'),
            const SizedBox(height: 16),
            Row(children: [
              if (existing != null)
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                  ),
                ),
              Expanded(
                child: FilledButton(
                  onPressed: (double.tryParse(ctrl.text) ?? 0) > 0 ? () => Navigator.pop(ctx, 'save') : null,
                  child: const Text('Save'),
                ),
              ),
            ]),
          ]);
        }),
      ),
    );
    if (result == null) return;
    try {
      if (result == 'delete') {
        await sb.from('budgets').delete().eq('id', existing!['id']);
      } else {
        await sb.from('budgets').upsert({
          'user_id': sb.auth.currentUser!.id,
          'category': cat,
          'monthly_limit': double.parse(ctrl.text),
        }, onConflict: 'user_id,category');
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final total = _cats.fold<double>(0, (s, c) => s + c.$2);
    final isCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;

    return Scaffold(
      appBar: AppBar(title: const Text('Spending Insights')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(
                child: Center(
                  child: Text('${months[_month.month - 1]} ${_month.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              IconButton(
                onPressed: isCurrent ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _Flow('Money in', _flow.$1, AppColors.success, Icons.south_west_rounded),
              const SizedBox(width: 8),
              _Flow('Spent', _flow.$2, AppColors.danger, Icons.north_east_rounded),
              const SizedBox(width: 8),
              _Flow('Saved', _flow.$3, scheme.primary, Icons.savings_rounded),
            ]),
            const SizedBox(height: 16),
            NovaCard(
              child: _loading
                  ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
                  : total == 0
                      ? SizedBox(
                          height: 160,
                          child: Center(
                            child: Text('No spending this month', style: TextStyle(color: scheme.onSurfaceVariant)),
                          ),
                        )
                      : Column(children: [
                          SizedBox(
                            height: 210,
                            child: Stack(alignment: Alignment.center, children: [
                              PieChart(PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 62,
                                pieTouchData: PieTouchData(touchCallback: (e, r) {
                                  setState(() => _touched = r?.touchedSection?.touchedSectionIndex);
                                }),
                                sections: [
                                  for (final (i, c) in _cats.indexed)
                                    PieChartSectionData(
                                      value: c.$2,
                                      color: catColor(c.$1),
                                      radius: _touched == i ? 34 : 28,
                                      showTitle: false,
                                    ),
                                ],
                              )),
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  _touched != null && _touched! >= 0 && _touched! < _cats.length
                                      ? _cats[_touched!].$1
                                      : 'Total spent',
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                ),
                                Text(
                                  formatMoney(
                                    _touched != null && _touched! >= 0 && _touched! < _cats.length ? _cats[_touched!].$2 : total,
                                    symbol: '₦',
                                    decimals: 0,
                                  ),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                                ),
                              ]),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          for (final c in _cats)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: catColor(c.$1), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w500))),
                                Text('${(c.$2 / total * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 96,
                                  child: Text(formatMoney(c.$2, symbol: '₦', decimals: 0),
                                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ),
                        ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Text('Budgets', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
              TextButton.icon(
                onPressed: _budgets.length >= budgetCategories.length ? null : () => _editBudget(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ]),
            const SizedBox(height: 6),
            if (_budgets.isEmpty)
              Text('Set monthly limits per category. NOVA alerts you at 80%.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
            else
              ..._budgets.map((b) {
                final limit = asDouble(b['monthly_limit']);
                final spent = _cats.where((c) => c.$1 == b['category']).fold<double>(0, (s, c) => s + c.$2);
                final pct = limit == 0 ? 0.0 : spent / limit;
                final color = pct >= 1 ? AppColors.danger : (pct >= 0.8 ? AppColors.warning : scheme.primary);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NovaCard(
                    onTap: () => _editBudget(b),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: catColor(b['category']), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(b['category'], style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('${formatMoney(spent, symbol: '₦', decimals: 0)} / ${formatMoney(limit, symbol: '₦', decimals: 0)}',
                            style: const TextStyle(fontSize: 13)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: pct.clamp(0, 1), minHeight: 8, color: color),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pct >= 1
                            ? 'Over budget by ${formatMoney(spent - limit, symbol: '₦', decimals: 0)}'
                            : '${formatMoney(limit - spent, symbol: '₦', decimals: 0)} left',
                        style: TextStyle(color: pct >= 1 ? AppColors.danger : scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ]),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Flow extends StatelessWidget {
  const _Flow(this.label, this.value, this.color, this.icon);
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: NovaCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(formatMoney(value, symbol: '₦', decimals: 0),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ]),
      ),
    );
  }
}
