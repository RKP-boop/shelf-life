// Screens 29–31 — one item.
//
// 29 Detail · 30 Edit · 31 Remove confirmation.
//
// Screen 29 is where Principle 4 is most visible: the expiry line is followed
// by the estimator's stored reason, so the number always explains itself. The
// reason is read from the row rather than recomputed, so the explanation the
// user saw when they added it is the one that persists even if the catalogue
// changes underneath.

import 'package:flutter/material.dart';

import '../../../core/engines/expiry_estimator.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/item_row.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/enums.dart';
import '../../../models/inventory_item.dart';

// ------------------------------------------------------------------ 29

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    super.key,
    required this.item,
    required this.expiryLine,
    this.recipeSuggestions = const [],
    this.onBack,
    this.onEdit,
    this.onUsedIt,
    this.onRemove,
    this.onQuantityChanged,
    this.onRecipeTap,
    this.today,
  });

  final InventoryItem item;

  /// Rendered date, e.g. "Best used by 28 August". Formatted by the caller so
  /// this screen holds no date-formatting locale decision.
  final String expiryLine;

  /// Recipes that use this item, ranked. Titles only — the scorer's number is
  /// never shown.
  final List<({String name, String matchLabel, String? imageKey})>
      recipeSuggestions;

  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onUsedIt;
  final VoidCallback? onRemove;
  final ValueChanged<int>? onQuantityChanged;
  final ValueChanged<String>? onRecipeTap;
  final DateTime? today;

  static const _estimator = ExpiryEstimator();

  static const _sourceLabel = {
    ExpirySource.user: 'You set this date',
    ExpirySource.printed: 'Printed on the pack',
    ExpirySource.estimated: 'Estimated for this item',
    ExpirySource.categoryDefault: 'Typical for this kind of thing',
  };

  @override
  Widget build(BuildContext context) {
    final now = today ?? DateTime.now();
    final freshness = _estimator.freshness(item.expiryDate, today: now);
    final badge = _estimator.badgeLabel(freshness, item.expiryDate, today: now);

    return AppScreen(
      child: Gutter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(
              onBack: onBack,
              trailingIcon: Icons.edit_outlined,
              onTrailing: onEdit,
            ),
            const SizedBox(height: 12),
            Center(
              child: ArtHalo(
                size: 210,
                colour: ProduceTile.tintFor(item.category),
                child: ProduceImage(
                  glyphKey: ItemRow.glyphFor(item),
                  category: item.category,
                  size: 148,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(item.productName, style: T.displayBold26)),
                if (badge != null) ...[
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FreshnessBadge(freshness: freshness, label: badge),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${ItemRow.quantityLabel(item)} · '
              '${_storage(item.storage)}',
              style: T.secondaryRegular13.copyWith(color: T.textSecondary),
            ),
            const SizedBox(height: 22),

            // The explainable-estimate card. The reason is the point of it.
            AppCard(
              colour: freshness == Freshness.fresh ? null : T.cardSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_outlined,
                          size: 19, color: T.accentPrimary),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(expiryLine, style: T.cardSemiBold15)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.expiryReason ??
                        'We do not have a reason recorded for this one.',
                    style: T.bodyRegular14.copyWith(color: T.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Pill(
                        _sourceLabel[item.expirySource] ??
                            item.expirySource.name,
                        icon: item.expirySource == ExpirySource.user
                            ? Icons.person_outline
                            : Icons.auto_awesome_outlined,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onEdit,
                        child: Text('Not right?',
                            style: T.labelMedium12
                                .copyWith(color: T.accentPrimary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How much is left', style: T.cardSemiBold15),
                        const SizedBox(height: 2),
                        Text('Used some? Bring it down.',
                            style: T.secondaryRegular13
                                .copyWith(color: T.textSecondary)),
                      ],
                    ),
                  ),
                  QuantityStepper(
                    value: item.quantity.round(),
                    onChanged: onQuantityChanged,
                    min: 0,
                  ),
                ],
              ),
            ),
            if (recipeSuggestions.isNotEmpty) ...[
              const SizedBox(height: 24),
              const SectionHeader('Ways to use it'),
              const SizedBox(height: 12),
              for (final r in recipeSuggestions) ...[
                AppCard(
                  onTap: () => onRecipeTap?.call(r.name),
                  radius: 20,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: T.tintMint,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: DishImage(imageKey: r.imageKey, size: 50),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: T.cardSemiBold15),
                            const SizedBox(height: 2),
                            Text(r.matchLabel,
                                style: T.secondaryRegular13
                                    .copyWith(color: T.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 20, color: T.textSecondary),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 24),
            AppButton(label: 'I used this', onPressed: onUsedIt),
            const SizedBox(height: 12),
            // "Take it off the list", not the word the PRD forbids. The action
            // is still a hard delete (D7) and the confirmation says so.
            AppButton.secondary(
                label: 'Take it off the list', onPressed: onRemove),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _storage(StorageLocation s) => switch (s) {
        StorageLocation.fridge => 'in the fridge',
        StorageLocation.freezer => 'in the freezer',
        StorageLocation.pantry => 'in the cupboard',
        StorageLocation.counter => 'on the counter',
      };
}

// ------------------------------------------------------------------ 30

/// Edit. BR-01: a user-set date always wins, and the screen says so — the
/// alternative is a user who changes a date, sees it silently re-estimated, and
/// stops trusting the app.
class EditItemScreen extends StatefulWidget {
  const EditItemScreen({
    super.key,
    required this.item,
    required this.expiryLabel,
    this.onBack,
    this.onSave,
    this.onPickDate,
    this.onRevertToEstimate,
  });

  final InventoryItem item;

  /// Rendered current date, supplied by the caller.
  final String expiryLabel;

  final VoidCallback? onBack;
  final void Function(String name, double quantity, String unit,
      StorageLocation storage, FoodCategory category)? onSave;
  final VoidCallback? onPickDate;
  final VoidCallback? onRevertToEstimate;

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.item.productName);
  late int _quantity = widget.item.quantity.round();
  late String _unit = widget.item.unit;
  late StorageLocation _storage = widget.item.storage;
  late FoodCategory _category = widget.item.category;

  static const _units = ['pcs', 'g', 'kg', 'ml', 'L', 'bunch', 'pack'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: widget.onBack, title: 'Edit'),
              const SizedBox(height: 18),
              AppTextField(
                label: 'Name',
                controller: _name,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text('How much', style: T.cardSemiBold15)),
                        QuantityStepper(
                          value: _quantity,
                          onChanged: (v) => setState(() => _quantity = v),
                          min: 0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final u in _units)
                          FilterPill(
                            label: u,
                            selected: u == _unit,
                            onTap: () => setState(() => _unit = u),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Best used by', style: T.cardSemiBold15),
                        ),
                        TextButton(
                          onPressed: widget.onPickDate,
                          child: Text(widget.expiryLabel,
                              style: T.labelMedium12
                                  .copyWith(color: T.accentPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.item.expirySource == ExpirySource.user
                          ? 'You set this date, so we will leave it alone.'
                          : 'Set your own date and we will stop estimating '
                              'this one.',
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary),
                    ),
                    if (widget.item.expirySource == ExpirySource.user) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: widget.onRevertToEstimate,
                        child: Text('Go back to our estimate',
                            style: T.labelMedium12
                                .copyWith(color: T.accentPrimary)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Where you keep it', style: T.cardSemiBold15),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final loc in StorageLocation.values)
                          FilterPill(
                            label: _storageLabel[loc] ?? loc.name,
                            selected: loc == _storage,
                            onTap: () => setState(() => _storage = loc),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text('What kind of thing', style: T.cardSemiBold15),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in FoodCategory.values)
                          FilterPill(
                            label: _categoryLabel[c] ?? c.name,
                            selected: c == _category,
                            onTap: () => setState(() => _category = c),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              AppButton(
                label: 'Save changes',
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => widget.onSave?.call(
                          _name.text.trim(),
                          _quantity.toDouble(),
                          _unit,
                          _storage,
                          _category,
                        ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );

  static const _storageLabel = {
    StorageLocation.fridge: 'Fridge',
    StorageLocation.freezer: 'Freezer',
    StorageLocation.pantry: 'Cupboard',
    StorageLocation.counter: 'Counter',
  };

  static const _categoryLabel = {
    FoodCategory.vegetables: 'Vegetables',
    FoodCategory.fruits: 'Fruit',
    FoodCategory.dairy: 'Dairy',
    FoodCategory.pantry: 'Pantry',
    FoodCategory.frozen: 'Frozen',
    FoodCategory.other: 'Something else',
  };
}

// ------------------------------------------------------------------ 31

/// Removal confirmation. BR-02 makes this irreversible and D7 means there is no
/// restore, so the sheet says exactly that rather than implying an undo.
///
/// It offers "I used it" as the primary action, because most removals are
/// actually consumption — and consumption is what the impact figures count.
class RemoveItemSheet extends StatelessWidget {
  const RemoveItemSheet({
    super.key,
    required this.item,
    this.onUsedIt,
    this.onRemove,
    this.onCancel,
  });

  final InventoryItem item;
  final VoidCallback? onUsedIt;
  final VoidCallback? onRemove;
  final VoidCallback? onCancel;

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
            const SizedBox(height: 22),
            Row(
              children: [
                ProduceTile(
                  glyphKey: ItemRow.glyphFor(item),
                  category: item.category,
                  size: 54,
                  radius: 17,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Taking ${item.productName} off the list',
                      style: T.titleSemiBold18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Did you use it, or is it going out? We count what gets used, so '
              'it is worth saying which.',
              style: T.bodyRegular14.copyWith(color: T.textSecondary),
            ),
            const SizedBox(height: 22),
            AppButton(label: 'I used it', onPressed: onUsedIt),
            const SizedBox(height: 12),
            AppButton.secondary(
                label: 'It is going out', onPressed: onRemove),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: onCancel,
                child: Text('Keep it',
                    style:
                        T.labelMedium12.copyWith(color: T.textSecondary)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Either way it comes off your list for good — there is no undo.',
              textAlign: TextAlign.center,
              style: T.chipSemiBold11.copyWith(color: T.textSecondary),
            ),
          ],
        ),
      );
}
