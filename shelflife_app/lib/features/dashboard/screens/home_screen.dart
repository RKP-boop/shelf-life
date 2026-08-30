// Screen 10 — Home hub.
//
// PRD 4.5's success metric: the user identifies today's priority within five
// seconds of opening. That is why "needs using" leads and the stats sit lower —
// if the numbers dominated, the screen would be optimising for vanity metrics
// rather than action.

import 'package:flutter/material.dart';

import '../../../core/engines/expiry_estimator.dart';
import '../../../core/engines/recipe_scorer.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/inventory_item.dart';
import '../../../models/models.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.kitchenTitle,
    required this.needsUsing,
    required this.suggestions,
    required this.stats,
    required this.shoppingCount,
    this.onTabChanged,
    this.onItemTap,
    this.onRecipeTap,
    this.onSearchTap,
    this.onNotificationsTap,
    this.onShoppingTap,
    this.today,
  });

  /// Rendered title, e.g. "Rakesh's kitchen" or "Your kitchen". Built by
  /// AppState, because whether a name exists is a session fact.
  final String kitchenTitle;
  final List<InventoryItem> needsUsing;
  final List<RecipeMatch> suggestions;
  final KitchenStats stats;
  final int shoppingCount;
  final ValueChanged<NavTab>? onTabChanged;
  final ValueChanged<InventoryItem>? onItemTap;
  final ValueChanged<RecipeMatch>? onRecipeTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onShoppingTap;
  final DateTime? today;

  static const _estimator = ExpiryEstimator();



  @override
  Widget build(BuildContext context) {
    final now = today ?? DateTime.now();
    return AppScreen(
      bottomBar: BottomNav(active: NavTab.home, onTap: onTabChanged),
      // No outer horizontal padding: the urgent-items row has to bleed to the
      // screen edge so a partially visible card signals "there is more here".
      // Everything else is guttered individually by [_g].
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Gutter(child: _header(now)),
          const SizedBox(height: 20),
          Gutter(child: GestureDetector(onTap: onSearchTap, child: const SearchField())),
          const SizedBox(height: 20),
          Gutter(child: _attentionBanner(now)),
          const SizedBox(height: 24),
          if (needsUsing.isNotEmpty) ...[
            Gutter(child: SectionHeader('Use these first',
                action: 'See all',
                onAction: () => onTabChanged?.call(NavTab.inventory))),
            const SizedBox(height: 12),
            _needsUsingRow(now),
            const SizedBox(height: 24),
          ],
          if (suggestions.isNotEmpty) ...[
            const Gutter(child: SectionHeader('Cook tonight')),
            const SizedBox(height: 12),
            for (final match in suggestions.take(2)) ...[
              Gutter(child: _recipeCard(match)),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
          ],
          if (shoppingCount > 0) Gutter(child: _shoppingRow()),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _header(DateTime now) {
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: T.accentPrimary),
                  const SizedBox(width: 4),
                  Text(greeting,
                      style:
                          T.labelMedium12.copyWith(color: T.textSecondary)),
                ],
              ),
              const SizedBox(height: 2),
              Text(kitchenTitle, style: T.titleSemiBold18),
            ],
          ),
        ),
        Stack(
          children: [
            CircleIconButton(
              icon: Icons.notifications_none,
              onPressed: onNotificationsTap,
            ),
            if (stats.dueToday > 0)
              Positioned(
                right: 9,
                top: 8,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: T.stateRedText,
                    shape: BoxShape.circle,
                    border: Border.all(color: T.cardBase, width: 1.6),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The hero. Leads with what needs attention, in words rather than numerals —
  /// "3 things need using today" is actionable where "3" alone is not.
  Widget _attentionBanner(DateTime now) {
    final count = needsUsing.length;
    final names = needsUsing.take(3).map((i) => i.productName).toList();

    if (count == 0) {
      return AppCard(
        radius: 26,
        colour: T.tintMint,
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Everything looks',
                      style: T.displayBold26.copyWith(color: T.accentPrimary)),
                  Text('fresh today',
                      style: T.displayBold26.copyWith(color: T.accentPrimary)),
                  const SizedBox(height: 6),
                  Text('Nothing needs your attention.',
                      style: T.secondaryRegular13
                          .copyWith(color: T.accentPrimary)),
                ],
              ),
            ),
            const ProduceImage(glyphKey: 'spinach', size: 74),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [T.tintMint, T.pageBlush],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count thing${count == 1 ? '' : 's'} need${count == 1 ? 's' : ''}',
                    style: T.displayBold26),
                const Text('using today', style: T.displayBold26),
                const SizedBox(height: 4),
                Text(
                  names.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      T.secondaryRegular13.copyWith(color: T.textSecondary),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'See what to cook',
                  expand: false,
                  onPressed: () => onTabChanged?.call(NavTab.recipes),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // One render at a readable size, not a stack of three: overlapping
          // 3D objects at 60dp turned into an unidentifiable mass. The count is
          // already stated in words, so the image only has to be appetising.
          ProduceImage(
            glyphKey: _glyphFor(needsUsing.first),
            category: needsUsing.first.category,
            size: 86,
          ),
        ],
      ),
    );
  }

  /// Horizontally scrolling cards, one per urgent item.
  Widget _needsUsingRow(DateTime now) => SizedBox(
        height: 178,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Gutter.width),
          clipBehavior: Clip.none,
          itemCount: needsUsing.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final item = needsUsing[i];
            final freshness =
                _estimator.freshness(item.expiryDate, today: now);
            return SizedBox(
              width: 148,
              child: AppCard(
                onTap: () => onItemTap?.call(item),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ProduceTile(
                        glyphKey: _glyphFor(item),
                        category: item.category,
                        size: 78,
                        radius: 999,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(item.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.cardSemiBold15),
                    const SizedBox(height: 2),
                    Text(_quantityLabel(item),
                        style: T.secondaryRegular13
                            .copyWith(color: T.textSecondary)),
                    const Spacer(),
                    FreshnessBadge(
                      freshness: freshness,
                      label: _estimator.badgeLabel(
                          freshness, item.expiryDate, today: now),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Widget _recipeCard(RecipeMatch match) => AppCard(
        onTap: () => onRecipeTap?.call(match),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: T.tintMint,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: DishImage(imageKey: match.imageKey, size: 66),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.name, style: T.cardSemiBold15),
                  const SizedBox(height: 3),
                  // The match count, never the score (spec §5.2).
                  Text('${match.matchLabel} · ${match.prepMinutes} min',
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary)),
                  if (match.urgencyLine != null) ...[
                    const SizedBox(height: 4),
                    Text(match.urgencyLine!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: T.chipSemiBold11
                            .copyWith(color: T.stateRedText)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: T.textSecondary),
          ],
        ),
      );

  Widget _shoppingRow() => AppCard(
        onTap: onShoppingTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        radius: 20,
        child: Row(
          children: [
            const Icon(Icons.shopping_basket_outlined,
                size: 22, color: T.accentPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$shoppingCount thing${shoppingCount == 1 ? '' : 's'} on your shopping list',
                style: T.bodyRegular14,
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: T.textSecondary),
          ],
        ),
      );

  /// Uses the glyph denormalised onto the row, falling back to the category
  /// marker for free-text items that never matched the catalogue.
  static String _glyphFor(InventoryItem item) =>
      item.glyphKey ??
      ProduceImage.categoryFallback[item.category] ??
      'cat-pantry';

  static String _quantityLabel(InventoryItem item) {
    final q = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);
    return '$q ${item.unit}';
  }
}
