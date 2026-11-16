import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkOf(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Center(
            child: Text('Cards',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.6,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: dark ? AppColors.balanceCardDark : AppColors.balanceCardLight,
                border: Border.all(color: AppColors.neon.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.contactless_rounded, color: Colors.white70),
                      Spacer(),
                      Text('NOVA',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              fontSize: 18)),
                    ],
                  ),
                  Spacer(),
                  Text('5399  ••••  ••••  9000',
                      style: TextStyle(
                          color: Colors.white, fontSize: 20, letterSpacing: 1.5)),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      Text('TEMIDAYO A.',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Spacer(),
                      Text('05/29', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(child: _CardAction(Icons.ac_unit_rounded, 'Freeze')),
              SizedBox(width: 10),
              Expanded(child: _CardAction(Icons.pin_outlined, 'PIN')),
              SizedBox(width: 10),
              Expanded(child: _CardAction(Icons.tune_rounded, 'Limits')),
            ],
          ),
          const SizedBox(height: 18),
          Text('Virtual and physical cards go live in Phase 8.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NovaCard(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
