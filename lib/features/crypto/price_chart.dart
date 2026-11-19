import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/models.dart';
import '../../core/data/nova_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';

/// Naira price chart with 1D / 7D / 30D / 1Y ranges and touch tooltips.
class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.symbol});
  final String symbol;
  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  static const _ranges = {'1D': '1', '7D': '7', '30D': '30', '1Y': '365'};
  String _range = '7D';
  List<(DateTime, double)> _points = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await context.read<NovaStore>().priceHistory(widget.symbol, _ranges[_range]!);
      if (mounted) setState(() => _points = p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = _points.length < 2 || _points.last.$2 >= _points.first.$2;
    final color = up ? AppColors.success : AppColors.danger;
    final change = _points.length < 2 ? 0.0 : (_points.last.$2 / _points.first.$2 - 1) * 100;

    return NovaCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 4),
          Text('Price (₦)', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(width: 8),
          if (_points.length > 1) ChangeChip(change),
          const Spacer(),
          for (final r in _ranges.keys)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() => _range = r);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _range == r ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(r,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _range == r ? scheme.primary : scheme.onSurfaceVariant,
                      )),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null || _points.length < 2
                  ? Center(
                      child: TextButton(onPressed: _load, child: Text(_error ?? 'No data. Tap to retry')),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => scheme.surfaceContainerHighest,
                            getTooltipItems: (spots) => spots.map((s) {
                              final t = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
                              return LineTooltipItem(
                                '${formatMoney(s.y, symbol: '₦')}\n${friendlyDate(t)}',
                                TextStyle(color: scheme.onSurface, fontSize: 11, fontWeight: FontWeight.w600),
                              );
                            }).toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _points
                                .map((p) => FlSpot(p.$1.millisecondsSinceEpoch.toDouble(), p.$2))
                                .toList(),
                            isCurved: true,
                            curveSmoothness: 0.2,
                            color: color,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ]),
    );
  }
}
