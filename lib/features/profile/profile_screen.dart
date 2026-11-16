import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/nova_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeController>();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Center(
            child: Text('Account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          NovaCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                  child: const Text('T',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Temidayo',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      Text('KYC Level 2 · Verified',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Appearance',
              style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          NovaCard(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                _ModeButton(
                  label: 'Light',
                  icon: Icons.light_mode_rounded,
                  selected: theme.mode == ThemeMode.light,
                  onTap: () => theme.setMode(ThemeMode.light),
                ),
                _ModeButton(
                  label: 'Dark',
                  icon: Icons.dark_mode_rounded,
                  selected: theme.mode == ThemeMode.dark,
                  onTap: () => theme.setMode(ThemeMode.dark),
                ),
                _ModeButton(
                  label: 'System',
                  icon: Icons.settings_suggest_rounded,
                  selected: theme.mode == ThemeMode.system,
                  onTap: () => theme.setMode(ThemeMode.system),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...const [
            (Icons.verified_user_outlined, 'Security & PIN'),
            (Icons.badge_outlined, 'Verification (KYC)'),
            (Icons.account_balance_outlined, 'Linked Banks'),
            (Icons.notifications_none_rounded, 'Notifications'),
            (Icons.help_outline_rounded, 'Help & Support'),
          ].map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NovaCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                onTap: () {},
                child: Row(
                  children: [
                    Icon(e.$1, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(e.$2,
                            style: const TextStyle(fontWeight: FontWeight.w500))),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? scheme.primary : Colors.transparent,
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20, color: selected ? Colors.white : scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : scheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
