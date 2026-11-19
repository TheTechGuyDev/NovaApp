import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/models.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/nova_widgets.dart';

SupabaseClient get adb => Supabase.instance.client;

/// Admin RPC wrapper: turns database errors into readable messages.
Future<dynamic> arpc(String fn, [Map<String, dynamic> params = const {}]) async {
  try {
    return await adb.rpc(fn, params: params);
  } on PostgrestException catch (e) {
    throw e.message;
  }
}

Future<Map<String, dynamic>> aops(String action, [Map<String, dynamic> params = const {}]) async {
  try {
    final r = await adb.functions.invoke('admin-ops', body: {'action': action, ...params});
    return Map<String, dynamic>.from(r.data as Map);
  } on FunctionException catch (e) {
    final d = e.details;
    throw d is Map ? '${d['error']}' : 'Request failed';
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.danger : null,
  ));
}

String ngn(dynamic v, {int decimals = 0}) => formatMoney(asDouble(v), symbol: '₦', decimals: decimals);

String dt(dynamic iso) {
  if (iso == null) return '-';
  final d = DateTime.parse(iso as String).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

bool isWide(BuildContext context) => MediaQuery.of(context).size.width >= 900;

/// Page frame: title, optional actions, scrollable body.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, required this.children, this.actions = const [], this.onRefresh});
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final pad = isWide(context) ? 28.0 : 16.0;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 10,
          children: [
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ...actions,
              if (onRefresh != null)
                IconButton.filledTonal(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
            ]),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.icon, this.color, this.sub});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color ?? scheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
        ],
      ]),
    );
  }
}

/// Grid that adapts column count to the screen width.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 640 ? 3 : 2);
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children.map((e) => SizedBox(width: w, child: e)).toList(),
      );
    });
  }
}

/// Table on wide screens, stacked cards on phones.
class ResponsiveTable extends StatelessWidget {
  const ResponsiveTable({super.key, required this.columns, required this.rows, this.onTap, this.empty = 'Nothing here yet'});
  final List<String> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onTap;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (rows.isEmpty) {
      return NovaCard(
        padding: const EdgeInsets.all(28),
        child: Center(child: Text(empty, style: TextStyle(color: scheme.onSurfaceVariant))),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 720) {
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NovaCard(
                  onTap: onTap == null ? null : () => onTap!(i),
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    for (var j = 0; j < columns.length; j++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 110,
                            child: Text(columns[j], style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          ),
                          Expanded(child: Align(alignment: Alignment.centerLeft, child: rows[i][j])),
                        ]),
                      ),
                  ]),
                ),
              ),
          ],
        );
      }
      return NovaCard(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
              columns: columns.map((h) => DataColumn(label: Text(h))).toList(),
              rows: [
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    onSelectChanged: onTap == null ? null : (_) => onTap!(i),
                    cells: rows[i].map((w) => DataCell(w)).toList(),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        switch (text) {
          'completed' || 'active' || 'filled' || 'verified' || 'Connected' => AppColors.success,
          'pending' || 'processing' || 'open' => AppColors.warning,
          'failed' || 'frozen' || 'suspended' || 'rejected' || 'reversed' => AppColors.danger,
          _ => Theme.of(context).colorScheme.onSurfaceVariant,
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

Future<String?> askText(BuildContext context, {required String title, String? hint, String? initial, bool obscure = false, String okLabel = 'Save'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: c,
          autofocus: true,
          obscureText: obscure,
          maxLines: obscure ? 1 : 3,
          minLines: 1,
          decoration: InputDecoration(hintText: hint),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(90, 44),
            backgroundColor: danger ? AppColors.danger : null,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}
