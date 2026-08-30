// Screens 24–28 and 32 — the inventory.
//
// 24 All · 25 Grouped by category · 26 Grouped by storage · 27 Sort and filter
// sheet · 28 Empty · 32 Inventory search.
//
// One screen with a grouping mode rather than three, because 24/25/26 differ
// only in how the same list is sectioned. Three separate screens would drift
// the moment a row gained a field.

import 'package:flutter/material.dart';

import '../../../core/engines/expiry_estimator.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/item_row.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/enums.dart';
import '../../../models/inventory_item.dart';

enum InventoryGrouping { none, category, storage }

enum InventorySort { soonestFirst, nameAZ, recentlyAdded }

extension InventorySortLabel on InventorySort {
  String get label => switch (this) {
        InventorySort.soonestFirst => 'Use soonest first',
        InventorySort.nameAZ => 'Name, A to Z',
        InventorySort.recentlyAdded => 'Recently added',
      };
}

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({
    super.key,
    required this.items,
    this.grouping = InventoryGrouping.none,
    this.sort = InventorySort.soonestFirst,
    this.storageFilter,
    this.categoryFilter,
    this.onTabChanged,
    this.onItemTap,
    this.onSearchTap,
    this.onFilterTap,
    this.onGroupingChanged,
    this.onAdd,
    this.today,
  });

  final List<InventoryItem> items;
  final InventoryGrouping grouping;
  final InventorySort sort;
  final StorageLocation? storageFilter;
  final FoodCategory? categoryFilter;
  final ValueChanged<NavTab>? onTabChanged;
  final ValueChanged<InventoryItem>? onItemTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onFilterTap;
  final ValueChanged<InventoryGrouping>? onGroupingChanged;
  final VoidCallback? onAdd;
  final DateTime? today;

  static const _estimator = ExpiryEstimator();

  static const categoryLabels = {
    FoodCategory.vegetables: 'Vegetables',
    FoodCategory.fruits: 'Fruit',
    FoodCategory.dairy: 'Dairy',
    FoodCategory.pantry: 'Pantry',
    FoodCategory.frozen: 'Frozen',
    FoodCategory.other: 'Everything else',
  };

  static const storageLabels = {
    StorageLocation.fridge: 'In the fridge',
    StorageLocation.freezer: 'In the freezer',
    StorageLocation.pantry: 'In the cupboard',
    StorageLocation.counter: 'On the counter',
  };

  List<InventoryItem> get _visible {
    var list = items.where((i) => i.status == ItemStatus.active).toList();
    if (storageFilter != null) {
      list = list.where((i) => i.storage == storageFilter).toList();
    }
    if (categoryFilter != null) {
      list = list.where((i) => i.category == categoryFilter).toList();
    }
    list.sort(switch (sort) {
      InventorySort.soonestFirst => (a, b) =>
          a.expiryDate.compareTo(b.expiryDate),
      InventorySort.nameAZ => (a, b) => a.productName
          .toLowerCase()
          .compareTo(b.productName.toLowerCase()),
      InventorySort.recentlyAdded => (a, b) =>
          b.createdAt.compareTo(a.createdAt),
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final now = today ?? DateTime.now();
    final visible = _visible;

    return AppScreen(
      bottomBar: BottomNav(active: NavTab.inventory, onTap: onTabChanged),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Gutter(child: _header(visible.length, now)),
          const SizedBox(height: 16),
          Gutter(
            child: GestureDetector(
              onTap: onSearchTap,
              child: SearchField(onFilterTap: onFilterTap),
            ),
          ),
          const SizedBox(height: 16),
          _groupingRow(),
          const SizedBox(height: 18),
          if (visible.isEmpty)
            Gutter(child: _empty())
          else
            ..._sections(visible, now),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _header(int count, DateTime now) {
    final urgent = _visible
        .where((i) =>
            _estimator.freshness(i.expiryDate, today: now) != Freshness.fresh)
        .length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your kitchen', style: T.displayBold26),
              const SizedBox(height: 2),
              Text(
                urgent == 0
                    ? '$count ${count == 1 ? 'thing' : 'things'}, all with '
                        'time in hand'
                    : '$count ${count == 1 ? 'thing' : 'things'} · $urgent to '
                        'use soon',
                style: T.secondaryRegular13.copyWith(color: T.textSecondary),
              ),
            ],
          ),
        ),
        CircleIconButton(icon: Icons.add, onPressed: onAdd),
      ],
    );
  }

  /// Grouping as pills rather than a dropdown: three options, all worth one
  /// tap, and a menu would hide the fact that grouping exists at all.
  Widget _groupingRow() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gutter.width),
        child: Row(
          children: [
            for (final g in InventoryGrouping.values) ...[
              if (g != InventoryGrouping.values.first)
                const SizedBox(width: 8),
              FilterPill(
                label: switch (g) {
                  InventoryGrouping.none => 'Everything',
                  InventoryGrouping.category => 'By kind',
                  InventoryGrouping.storage => 'By where it is',
                },
                selected: g == grouping,
                onTap: () => onGroupingChanged?.call(g),
              ),
            ],
            const SizedBox(width: 8),
            Pill(sort.label, icon: Icons.sort),
          ],
        ),
      );

  List<Widget> _sections(List<InventoryItem> visible, DateTime now) {
    if (grouping == InventoryGrouping.none) {
      return [
        for (final item in visible) ...[
          Gutter(child: _row(item, now)),
          const SizedBox(height: 10),
        ],
      ];
    }

    // Preserve the enum's declared order so section order is stable rather
    // than dependent on what happens to be in the kitchen today.
    final buckets = <String, List<InventoryItem>>{};
    if (grouping == InventoryGrouping.category) {
      for (final c in FoodCategory.values) {
        final rows = visible.where((i) => i.category == c).toList();
        if (rows.isNotEmpty) buckets[categoryLabels[c] ?? c.name] = rows;
      }
    } else {
      for (final loc in StorageLocation.values) {
        final rows = visible.where((i) => i.storage == loc).toList();
        if (rows.isNotEmpty) buckets[storageLabels[loc] ?? loc.name] = rows;
      }
    }

    return [
      for (final entry in buckets.entries) ...[
        Gutter(
          child: SectionHeader(
            entry.key,
            action: '${entry.value.length}',
          ),
        ),
        const SizedBox(height: 10),
        for (final item in entry.value) ...[
          Gutter(child: _row(item, now)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _row(InventoryItem item, DateTime now) {
    final freshness = _estimator.freshness(item.expiryDate, today: now);
    return ItemRow(
      item: item,
      freshness: freshness,
      badgeLabel: _estimator.badgeLabel(freshness, item.expiryDate, today: now),
      onTap: () => onItemTap?.call(item),
    );
  }

  // ---------------------------------------------------------------- 28

  Widget _empty() {
    final filtered = storageFilter != null || categoryFilter != null;
    return EmptyState(
      title: filtered ? 'Nothing here yet' : 'Your kitchen is empty',
      body: filtered
          ? 'Nothing matches that filter. Clear it to see everything you have.'
          : 'Add a few things and ShelfLife will keep an eye on what needs '
              'using.',
      artwork: const ProduceImage(glyphKey: 'cat-vegetables', size: 104),
      action: filtered ? 'Show everything' : 'Add something',
      onAction: filtered ? () => onGroupingChanged?.call(grouping) : onAdd,
    );
  }
}

// ------------------------------------------------------------------ 27

/// Sort and filter, as a bottom sheet. A sheet rather than a screen because the
/// list behind it is the context for the choice.
class InventoryFilterSheet extends StatelessWidget {
  const InventoryFilterSheet({
    super.key,
    required this.sort,
    this.storageFilter,
    this.categoryFilter,
    this.onSortChanged,
    this.onStorageChanged,
    this.onCategoryChanged,
    this.onApply,
    this.onClear,
  });

  final InventorySort sort;
  final StorageLocation? storageFilter;
  final FoodCategory? categoryFilter;
  final ValueChanged<InventorySort>? onSortChanged;
  final ValueChanged<StorageLocation?>? onStorageChanged;
  final ValueChanged<FoodCategory?>? onCategoryChanged;
  final VoidCallback? onApply;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: T.cardBase,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: T.structureBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Sort and filter', style: T.titleSemiBold18)),
                TextButton(
                  onPressed: onClear,
                  child: Text('Clear all',
                      style:
                          T.labelMedium12.copyWith(color: T.accentPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Order', style: T.cardSemiBold15),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in InventorySort.values)
                  FilterPill(
                    label: s.label,
                    selected: s == sort,
                    onTap: () => onSortChanged?.call(s),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Text('Where it is', style: T.cardSemiBold15),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterPill(
                  label: 'Anywhere',
                  selected: storageFilter == null,
                  onTap: () => onStorageChanged?.call(null),
                ),
                for (final loc in StorageLocation.values)
                  FilterPill(
                    label: InventoryScreen.storageLabels[loc] ?? loc.name,
                    selected: loc == storageFilter,
                    onTap: () => onStorageChanged?.call(loc),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Text('What kind', style: T.cardSemiBold15),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterPill(
                  label: 'Anything',
                  selected: categoryFilter == null,
                  onTap: () => onCategoryChanged?.call(null),
                ),
                for (final c in FoodCategory.values)
                  FilterPill(
                    label: InventoryScreen.categoryLabels[c] ?? c.name,
                    selected: c == categoryFilter,
                    onTap: () => onCategoryChanged?.call(c),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            AppButton(label: 'Show these', onPressed: onApply),
          ],
        ),
      );
}
