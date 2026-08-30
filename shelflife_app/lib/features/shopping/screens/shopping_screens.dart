// Screens 39–41 — the shopping list.
//
// 39 List · 40 Add to list · 41 Empty.
//
// The caption under each row is the `source` enum, rendered: "Added from Palak
// paneer", "You ran out", or nothing for something typed by hand. That is why
// the enum exists rather than a free-text note — the caption cannot drift from
// the reason the row was created.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/models.dart';

// ------------------------------------------------------------------ 39

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({
    super.key,
    required this.items,
    this.onBack,
    this.onTogglePurchased,
    this.onAdd,
    this.onRemove,
    this.onClearPurchased,
    this.glyphOf,
  });

  final List<ShoppingListItem> items;
  final VoidCallback? onBack;
  final ValueChanged<ShoppingListItem>? onTogglePurchased;
  final VoidCallback? onAdd;
  final ValueChanged<ShoppingListItem>? onRemove;
  final VoidCallback? onClearPurchased;

  /// Resolves a row to a glyph. Injected so this screen holds no catalogue.
  final String Function(ShoppingListItem)? glyphOf;

  List<ShoppingListItem> get _open =>
      items.where((i) => !i.purchased).toList();

  List<ShoppingListItem> get _done =>
      items.where((i) => i.purchased).toList();

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final done = _done;

    return AppScreen(
      floating: items.isEmpty
          ? null
          : Positioned(
              right: 24,
              bottom: 28,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x3D0A7A55),
                        offset: Offset(0, 8),
                        blurRadius: 20),
                  ],
                ),
                child: Material(
                  color: T.accentPrimary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onAdd,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 58,
                      height: 58,
                      child:
                          Icon(Icons.add, size: 26, color: T.textOnAccent),
                    ),
                  ),
                ),
              ),
            ),
      child: Gutter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(onBack: onBack),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shopping list', style: T.displayBold26),
                      const SizedBox(height: 2),
                      Text(
                        open.isEmpty && done.isEmpty
                            ? 'Nothing on it yet'
                            : '${open.length} to get'
                                '${done.isEmpty ? '' : ' · ${done.length} in the basket'}',
                        style: T.secondaryRegular13
                            .copyWith(color: T.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (items.isEmpty)
              _empty()
            else ...[
              for (final item in open) ...[
                _Row(
                  item: item,
                  glyphKey: glyphOf?.call(item),
                  onToggle: () => onTogglePurchased?.call(item),
                  onRemove: () => onRemove?.call(item),
                ),
                const SizedBox(height: 10),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionHeader('In the basket',
                    action: 'Clear these', onAction: onClearPurchased),
                const SizedBox(height: 10),
                for (final item in done) ...[
                  _Row(
                    item: item,
                    glyphKey: glyphOf?.call(item),
                    onToggle: () => onTogglePurchased?.call(item),
                    onRemove: () => onRemove?.call(item),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 90),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 41

  Widget _empty() => EmptyState(
        title: 'Nothing to get',
        body: 'Things land here when you run out, or when a recipe needs '
            'something you do not have. You can add your own too.',
        artwork: const ProduceImage(glyphKey: 'cat-fruits', size: 100),
        action: 'Add something',
        onAction: onAdd,
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    this.glyphKey,
    this.onToggle,
    this.onRemove,
  });

  final ShoppingListItem item;
  final String? glyphKey;
  final VoidCallback? onToggle;
  final VoidCallback? onRemove;

  /// The caption comes from the model, where the source enum owns it. A second
  /// copy of that switch here is exactly how the caption and the reason drift
  /// apart.
  String? get _caption => item.caption;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onToggle,
        radius: 20,
        padding: const EdgeInsets.all(12),
        colour: item.purchased ? T.cardSoft : null,
        child: Row(
          children: [
            Icon(
              item.purchased ? Icons.check_circle : Icons.circle_outlined,
              size: 24,
              color: item.purchased ? T.accentPrimary : T.structureBorder,
            ),
            const SizedBox(width: 12),
            if (glyphKey != null) ...[
              ProduceImage(glyphKey: glyphKey!, size: 34),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: item.purchased
                        ? T.cardSemiBold15.copyWith(
                            color: T.textSecondary,
                            decoration: TextDecoration.lineThrough,
                          )
                        : T.cardSemiBold15,
                  ),
                  if (_caption != null) ...[
                    const SizedBox(height: 2),
                    Text(_caption!,
                        style: T.chipSemiBold11
                            .copyWith(color: T.textSecondary)),
                  ],
                ],
              ),
            ),
            Text(
              '${_qty(item.quantity)}'
              '${item.unit == null ? '' : ' ${item.unit}'}',
              style: T.secondaryRegular13.copyWith(color: T.textSecondary),
            ),
            IconButton(
              onPressed: onRemove,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: 'Take it off',
              icon: const Icon(Icons.close, color: T.textSecondary),
            ),
          ],
        ),
      );

  static String _qty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(1);
}

// ------------------------------------------------------------------ 40

class AddToListScreen extends StatefulWidget {
  const AddToListScreen({
    super.key,
    this.onBack,
    this.onAdd,
    this.suggestions = const [],
    this.alreadyHave = const [],
  });

  final VoidCallback? onBack;
  final void Function(String name, double? quantity, String? unit)? onAdd;
  final List<String> suggestions;

  /// Names already in the kitchen. Surfaced rather than blocked: the user may
  /// well want more, but they should know before they buy it twice.
  final List<String> alreadyHave;

  @override
  State<AddToListScreen> createState() => _AddToListScreenState();
}

class _AddToListScreenState extends State<AddToListScreen> {
  final _name = TextEditingController();
  int _quantity = 1;
  String _unit = 'pcs';

  static const _units = ['pcs', 'g', 'kg', 'ml', 'L', 'bunch', 'pack'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _duplicate => widget.alreadyHave
      .any((n) => n.toLowerCase() == _name.text.trim().toLowerCase());

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: widget.onBack, title: 'Add to the list'),
              const SizedBox(height: 20),
              AppTextField(
                label: 'What do you need',
                hint: 'Cream, coriander, toor dal…',
                controller: _name,
                icon: Icons.search,
                onChanged: (_) => setState(() {}),
              ),
              if (_duplicate) ...[
                const SizedBox(height: 14),
                InfoStrip(
                  'You already have ${_name.text.trim()} in. Still worth '
                  'adding if you want more.',
                  icon: Icons.inventory_2_outlined,
                ),
              ],
              if (widget.suggestions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Things you buy often',
                    style:
                        T.labelMedium12.copyWith(color: T.textSecondary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in widget.suggestions)
                      FilterPill(
                        label: s,
                        selected: s.toLowerCase() ==
                            _name.text.trim().toLowerCase(),
                        onTap: () => setState(() => _name.text = s),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('How much', style: T.cardSemiBold15),
                              const SizedBox(height: 2),
                              Text('Optional — leave it if you are not sure.',
                                  style: T.secondaryRegular13
                                      .copyWith(color: T.textSecondary)),
                            ],
                          ),
                        ),
                        QuantityStepper(
                          value: _quantity,
                          onChanged: (v) => setState(() => _quantity = v),
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
              const SizedBox(height: 26),
              AppButton(
                label: 'Add to the list',
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => widget.onAdd?.call(
                        _name.text.trim(), _quantity.toDouble(), _unit),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}
