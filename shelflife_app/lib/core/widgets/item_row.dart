library;

import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';
import '../../models/enums.dart';
import '../../models/inventory_item.dart';
import 'app_widgets.dart';
import 'produce_image.dart';

/// A single inventory row: image, name, quantity and storage, freshness badge.
///
/// The one widget in `core/widgets` that knows a model. Inventory, search,
/// recipes and the shopping list all render this row, and a shared row bound to
/// [InventoryItem] is better than three features importing each other.
class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.item,
    required this.freshness,
    required this.badgeLabel,
    this.onTap,
    this.trailing,
  });

  final InventoryItem item;
  final Freshness freshness;
  final String? badgeLabel;
  final VoidCallback? onTap;
  final Widget? trailing;

  static String quantityLabel(InventoryItem item) {
    final q = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);
    return '$q ${item.unit}';
  }

  static String glyphFor(InventoryItem item) =>
      item.glyphKey ??
      ProduceImage.categoryFallback[item.category] ??
      'cat-pantry';

  static const _storageLabel = {
    StorageLocation.fridge: 'Fridge',
    StorageLocation.freezer: 'Freezer',
    StorageLocation.pantry: 'Pantry',
    StorageLocation.counter: 'Counter',
  };

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 22,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ProduceTile(
              glyphKey: glyphFor(item),
              category: item.category,
              size: 54,
              radius: 17,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cardSemiBold15),
                  const SizedBox(height: 3),
                  Text(
                    '${quantityLabel(item)} · '
                    '${_storageLabel[item.storage] ?? item.storage.name}',
                    style:
                        T.secondaryRegular13.copyWith(color: T.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                FreshnessBadge(freshness: freshness, label: badgeLabel),
          ],
        ),
      );
}
