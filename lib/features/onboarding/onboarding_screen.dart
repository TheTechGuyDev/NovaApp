import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_widgets.dart';
import '../auth/auth_screens.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: dark
                    ? const RadialGradient(
                        center: Alignment(0.3, -0.6),
                        radius: 1.1,
                        colors: [Color(0xFF145A30), AppColors.darkBg],
                      )
                    : const RadialGradient(
                        center: Alignment(0.3, -0.6),
                        radius: 1.1,
                        colors: [Color(0xFFBBF7D0), AppColors.lightBg],
                      ),
              ),
            ),
          ),
          const Positioned.fill(child: GridBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset('assets/brand/nova_icon.png', width: 36, height: 36),
                      ),
                      const SizedBox(width: 10),
                      Text('NOVA',
                          style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800, letterSpacing: 2)),
                    ],
                  ),
                  const Expanded(child: _CardStack()),
                  Text(
                    'Gateway to\nSmarter Digital\nFinance',
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.08,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Manage your Naira, crypto and cards in one secure space.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => _open(context, const SignUpScreen()),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Get Started'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _open(context, const SignInScreen()),
                      child: const Text('I already have an account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardStack extends StatelessWidget {
  const _CardStack();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: const Offset(40, -40),
              child: Transform.rotate(
                angle: -math.pi / 14,
                child: const _MiniCard(opacity: 0.55),
              ),
            ),
            Transform.rotate(
              angle: -math.pi / 9,
              child: const _MiniCard(opacity: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 270,
        height: 168,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: AppColors.balanceCardDark,
          border: Border.all(color: AppColors.neon.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text('NOVA',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic)),
            ),
            Spacer(),
            Text('Total Balance',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            SizedBox(height: 2),
            Text('₦2,450,000.00',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            Text('**** 9000',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
