/// Bottom navigation, mirroring the Figma component.
///
/// Five slots with the Scan action elevated at centre, so the primary action is
/// reachable one-handed (PRD 4.2). Cells are equal width with a real gap, so
/// adjacent tap targets are separated rather than touching.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.g.dart';

enum NavTab { home, inventory, scan, recipes, profile }

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.active, this.onTap});

  final NavTab active;
  final ValueChanged<NavTab>? onTap;

  static const _items = [
    (NavTab.home, Icons.home_outlined, 'Home'),
    (NavTab.inventory, Icons.grid_view_outlined, 'Inventory'),
    (NavTab.recipes, Icons.ramen_dining_outlined, 'Recipes'),
    (NavTab.profile, Icons.person_outline, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 96,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 78,
                decoration: const BoxDecoration(
                  color: T.cardBase,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A0D2119),
                      offset: Offset(0, -6),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (final (tab, icon, label) in _items.take(2))
                      _cell(tab, icon, label),
                    // the elevated Scan button occupies this gap
                    const SizedBox(width: 76),
                    for (final (tab, icon, label) in _items.skip(2))
                      _cell(tab, icon, label),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 34,
              child: Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.accentShadow,
                  ),
                  child: Material(
                    color: T.accentPrimary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => onTap?.call(NavTab.scan),
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 60,
                        height: 60,
                        child: Icon(Icons.qr_code_scanner,
                            size: 27, color: T.textOnAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _cell(NavTab tab, IconData icon, String label) {
    final on = tab == active;
    final colour = on ? T.accentPrimary : T.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: () => onTap?.call(tab),
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          // 48dp minimum tap height (PRD 4.11), even though the visual
          // content is smaller.
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 23, color: colour),
              const SizedBox(height: 3),
              Text(label, style: T.navMedium11.copyWith(color: colour)),
            ],
          ),
        ),
      ),
    );
  }
}
