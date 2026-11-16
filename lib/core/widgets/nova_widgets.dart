import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

bool isDarkOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Rounded surface card with a thin border, used across the app.
class NovaCard extends StatelessWidget {
  const NovaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            color: gradient == null ? scheme.surface : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.8)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Faint grid lines behind hero sections, like the reference design.
class GridBackground extends StatelessWidget {
  const GridBackground({super.key, this.spacing = 28});
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final color = isDarkOf(context)
        ? Colors.white.withValues(alpha: 0.04)
        : AppColors.primaryDeep.withValues(alpha: 0.06);
    return CustomPaint(painter: _GridPainter(color, spacing), size: Size.infinite);
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color, this.spacing);
  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}

/// Circular icon button with a subtle border (bell, back, etc).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, this.onTap, this.size = 44});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.6),
      shape: CircleBorder(side: BorderSide(color: scheme.outline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 20, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// Small coloured chip showing a percentage change.
class ChangeChip extends StatelessWidget {
  const ChangeChip(this.change, {super.key});
  final double change;

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final c = up ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${up ? '+' : ''}${change.toStringAsFixed(2)}%',
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Simple coin avatar (letter in a coloured circle) so we need no logo assets.
class CoinAvatar extends StatelessWidget {
  const CoinAvatar({super.key, required this.symbol, required this.color, this.size = 36});
  final String symbol;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        symbol.length > 4 ? symbol.substring(0, 4) : symbol,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * (symbol.length > 3 ? 0.24 : 0.3),
        ),
      ),
    );
  }
}
