// Screens 20–23 — barcode and manual entry.
//
// 20 Barcode scanner · 21 Product found · 22 Product not known yet ·
// 23 Add by hand.
//
// D1 makes the seeded `products` table the sole barcode lookup path: no
// external API. That is why screen 22 exists and is a normal outcome rather
// than a failure — the user types it once and the row is cached, which is the
// promise "we will remember it for next time".

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/enums.dart';

// ------------------------------------------------------------------ 20

class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({
    super.key,
    this.viewfinder,
    this.onBack,
    this.onByHand,
    this.torchOn = false,
    this.onToggleTorch,
    this.lastScanned,
  });

  final Widget? viewfinder;
  final VoidCallback? onBack;
  final VoidCallback? onByHand;
  final bool torchOn;
  final VoidCallback? onToggleTorch;

  /// Shown briefly after a successful read, so a scan that worked is visibly
  /// acknowledged before the next screen arrives.
  final String? lastScanned;

  static final _chrome = T.overlayScrim.withValues(alpha: 0.55);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: T.overlayScrim,
        body: Stack(
          fit: StackFit.expand,
          children: [
            viewfinder ?? const ColoredBox(color: T.overlayScrim),
            const _ScanWindow(),
            const CameraScrim(top: 170, bottom: 260),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _Circle(icon: Icons.arrow_back, onTap: onBack),
                        const Spacer(),
                        _Circle(
                          icon: torchOn
                              ? Icons.flashlight_on
                              : Icons.flashlight_off,
                          onTap: onToggleTorch,
                          active: torchOn,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _chrome,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      lastScanned == null
                          ? 'Hold the barcode inside the window.'
                          : 'Read $lastScanned',
                      textAlign: TextAlign.center,
                      style: T.secondaryRegular13
                          .copyWith(color: T.textOnAccent),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: onByHand,
                    child: Text('Add by hand instead',
                        style: T.labelMedium12
                            .copyWith(color: T.textOnAccent)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      );
}

/// A landscape window rather than the square used for QR codes: barcodes are
/// wide, and a square window invites the user to hold the phone wrongly.
class _ScanWindow extends StatelessWidget {
  const _ScanWindow();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 290,
          height: 170,
          decoration: BoxDecoration(
            border: Border.all(color: T.textOnAccent, width: 2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              color: T.accentBright,
            ),
          ),
        ),
      );
}

class _Circle extends StatelessWidget {
  const _Circle({required this.icon, this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: active
            ? T.textOnAccent
            : T.overlayScrim.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon,
                size: 21,
                color: active ? T.textPrimary : T.textOnAccent),
          ),
        ),
      );
}

// ------------------------------------------------------------------ 21

class BarcodeFoundScreen extends StatelessWidget {
  const BarcodeFoundScreen({
    super.key,
    required this.productName,
    required this.brand,
    required this.category,
    required this.glyphKey,
    required this.barcode,
    required this.expiryLine,
    required this.expiryReason,
    this.quantity = 1,
    this.onQuantityChanged,
    this.storage = StorageLocation.fridge,
    this.onStorageChanged,
    this.onConfirm,
    this.onEditExpiry,
    this.onBack,
    this.fromCache = true,
  });

  final String productName;
  final String? brand;
  final FoodCategory category;
  final String glyphKey;
  final String barcode;

  /// Rendered form of the estimate, e.g. "Best by 4 September".
  final String expiryLine;

  /// The estimator's plain-English justification. Principle 4: the estimate
  /// explains itself, and the explanation is stored rather than reconstructed.
  final String expiryReason;

  final int quantity;
  final ValueChanged<int>? onQuantityChanged;
  final StorageLocation storage;
  final ValueChanged<StorageLocation>? onStorageChanged;
  final VoidCallback? onConfirm;
  final VoidCallback? onEditExpiry;
  final VoidCallback? onBack;
  final bool fromCache;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack, title: 'Check and add'),
              const SizedBox(height: 18),
              Center(
                child: ArtHalo(
                  size: 180,
                  colour: ProduceTile.tintFor(category),
                  child: ProduceImage(
                      glyphKey: glyphKey, category: category, size: 124),
                ),
              ),
              const SizedBox(height: 20),
              Text(productName, style: T.displayBold26),
              if (brand != null) ...[
                const SizedBox(height: 2),
                Text(brand!,
                    style:
                        T.secondaryRegular13.copyWith(color: T.textSecondary)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Pill(barcode, icon: Icons.qr_code_2),
                  const SizedBox(width: 8),
                  if (fromCache)
                    const Pill('Known product', icon: Icons.check),
                ],
              ),
              const SizedBox(height: 22),
              AppCard(
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
                        TextButton(
                          onPressed: onEditExpiry,
                          child: Text('Change',
                              style: T.labelMedium12
                                  .copyWith(color: T.accentPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(expiryReason,
                        style: T.secondaryRegular13
                            .copyWith(color: T.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _QuantityAndStorage(
                quantity: quantity,
                onQuantityChanged: onQuantityChanged,
                storage: storage,
                onStorageChanged: onStorageChanged,
              ),
              const SizedBox(height: 26),
              AppButton(label: 'Add to my kitchen', onPressed: onConfirm),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

/// Quantity plus storage, together because changing storage changes the expiry
/// estimate and the two belong in one glance.
class _QuantityAndStorage extends StatelessWidget {
  const _QuantityAndStorage({
    required this.quantity,
    required this.onQuantityChanged,
    required this.storage,
    required this.onStorageChanged,
  });

  final int quantity;
  final ValueChanged<int>? onQuantityChanged;
  final StorageLocation storage;
  final ValueChanged<StorageLocation>? onStorageChanged;

  static const labels = {
    StorageLocation.fridge: 'Fridge',
    StorageLocation.freezer: 'Freezer',
    StorageLocation.pantry: 'Pantry',
    StorageLocation.counter: 'Counter',
  };

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('How many', style: T.cardSemiBold15)),
                QuantityStepper(value: quantity, onChanged: onQuantityChanged),
              ],
            ),
            const SizedBox(height: 18),
            Text('Where you keep it', style: T.cardSemiBold15),
            const SizedBox(height: 4),
            Text('Changing this changes how long it keeps.',
                style: T.secondaryRegular13.copyWith(color: T.textSecondary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final loc in StorageLocation.values)
                  FilterPill(
                    label: labels[loc] ?? loc.name,
                    selected: loc == storage,
                    onTap: () => onStorageChanged?.call(loc),
                  ),
              ],
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 22

class BarcodeUnknownScreen extends StatelessWidget {
  const BarcodeUnknownScreen({
    super.key,
    required this.barcode,
    this.onAddByHand,
    this.onScanAnother,
    this.onBack,
    this.offline = false,
  });

  final String barcode;

  /// True when the lookup could not reach the internet, as opposed to reaching
  /// it and finding nothing. Different situations deserve different copy: one
  /// is worth retrying later, the other is not.
  final bool offline;
  final VoidCallback? onAddByHand;
  final VoidCallback? onScanAnother;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const SizedBox(height: 24),
              Center(
                child: ArtHalo(
                  size: 180,
                  colour: T.tintLemon,
                  child: Icon(Icons.qr_code_2,
                      size: 86, color: T.accentPrimary),
                ),
              ),
              const SizedBox(height: 26),
              ScreenTitle(
                offline
                    ? const ['Cannot look', 'that one up']
                    : const ['New one', 'on us'],
                subtitle: offline
                    ? 'No connection, so we could not check what this is. Tell '
                        'us and we will remember it — or try again once you '
                        'are back online.'
                    : 'We have not seen this barcode before, and it is not in '
                        'the open product database either. Tell us what it is '
                        'once and we will remember it for next time.',
              ),
              const SizedBox(height: 18),
              Row(children: [Pill(barcode, icon: Icons.qr_code_2)]),
              const SizedBox(height: 24),
              AppButton(label: 'Tell us what it is', onPressed: onAddByHand),
              const SizedBox(height: 12),
              AppButton.secondary(
                  label: 'Scan a different one', onPressed: onScanAnother),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------ 23

/// Add by hand. The one screen that must work for anything, so the name field
/// accepts free text — an unmatched name is saved locally and offered as a
/// suggestion next time rather than rejected.
class AddByHandScreen extends StatefulWidget {
  const AddByHandScreen({
    super.key,
    this.onBack,
    this.onSave,
    this.onNameChanged,
    this.suggestions = const [],
    this.prefilledName,
    this.prefilledBarcode,
    this.expiryPreview,
    this.expiryReason,
  });

  final VoidCallback? onBack;
  final void Function(String name, int quantity, String unit,
      StorageLocation storage, FoodCategory category)? onSave;

  /// Reports each keystroke so the caller can look up catalogue matches. The
  /// screen holds no catalogue of its own.
  final ValueChanged<String>? onNameChanged;

  /// Catalogue matches for what has been typed so far.
  final List<String> suggestions;

  final String? prefilledName;
  final String? prefilledBarcode;

  /// Live estimate for the current selection, so the user sees the consequence
  /// of the storage choice before saving rather than after.
  final String? expiryPreview;
  final String? expiryReason;

  @override
  State<AddByHandScreen> createState() => _AddByHandScreenState();
}

class _AddByHandScreenState extends State<AddByHandScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.prefilledName ?? '');
  int _quantity = 1;
  String _unit = 'pcs';
  StorageLocation _storage = StorageLocation.fridge;
  FoodCategory _category = FoodCategory.vegetables;

  static const _units = ['pcs', 'g', 'kg', 'ml', 'L', 'bunch', 'pack'];

  static const _categoryLabels = {
    FoodCategory.vegetables: 'Vegetables',
    FoodCategory.fruits: 'Fruit',
    FoodCategory.dairy: 'Dairy',
    FoodCategory.pantry: 'Pantry',
    FoodCategory.frozen: 'Frozen',
    FoodCategory.other: 'Something else',
  };

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
              TopBar(onBack: widget.onBack, title: 'Add by hand'),
              const SizedBox(height: 16),
              if (widget.prefilledBarcode != null) ...[
                InfoStrip(
                  'Saving this will link it to barcode '
                  '${widget.prefilledBarcode}, so the next scan is instant.',
                  icon: Icons.qr_code_2,
                ),
                const SizedBox(height: 18),
              ],
              AppTextField(
                label: 'What is it',
                hint: 'Spinach, paneer, toor dal…',
                controller: _name,
                icon: Icons.search,
                onChanged: (text) {
                  setState(() {});
                  widget.onNameChanged?.call(text);
                },
                helper: 'Anything at all — if we do not know it yet, we will '
                    'remember it for you.',
              ),
              if (widget.suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in widget.suggestions)
                      FilterPill(
                        label: s,
                        selected: s.toLowerCase() ==
                            _name.text.trim().toLowerCase(),
                        onTap: () {
                          setState(() => _name.text = s);
                          widget.onNameChanged?.call(s);
                        },
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
                            child: Text('How much', style: T.cardSemiBold15)),
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
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What kind of thing', style: T.cardSemiBold15),
                    const SizedBox(height: 4),
                    Text('Sets the fallback shelf life if we do not know it.',
                        style: T.secondaryRegular13
                            .copyWith(color: T.textSecondary)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in FoodCategory.values)
                          FilterPill(
                            label: _categoryLabels[c] ?? c.name,
                            selected: c == _category,
                            onTap: () => setState(() => _category = c),
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
                    Text('Where you keep it', style: T.cardSemiBold15),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final loc in StorageLocation.values)
                          FilterPill(
                            label:
                                _QuantityAndStorage.labels[loc] ?? loc.name,
                            selected: loc == _storage,
                            onTap: () => setState(() => _storage = loc),
                          ),
                      ],
                    ),
                    if (widget.expiryPreview != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: T.tintMint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.expiryPreview!,
                                style: T.labelMedium12
                                    .copyWith(color: T.accentPrimary)),
                            if (widget.expiryReason != null) ...[
                              const SizedBox(height: 3),
                              Text(widget.expiryReason!,
                                  style: T.chipSemiBold11
                                      .copyWith(color: T.accentPrimary)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 26),
              AppButton(
                label: 'Add to my kitchen',
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => widget.onSave?.call(_name.text.trim(), _quantity,
                        _unit, _storage, _category),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}
