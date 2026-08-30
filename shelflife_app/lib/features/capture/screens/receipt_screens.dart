// Screens 13–19 — the receipt capture flow.
//
// 13 Scan chooser · 14 Receipt camera · 15 Reading receipt · 16 Review and
// confirm · 17 A row that needs input · 18 Added summary · 19 Receipt
// unreadable.
//
// The whole flow rests on one stance from the spec: never guess. A line the
// parser cannot resolve is still shown, marked as needing input, because
// silently adding the wrong thing to someone's kitchen is worse than asking.

import 'package:flutter/material.dart';

import '../../../core/engines/receipt_parser.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/enums.dart';

// ------------------------------------------------------------------ 13

class ScanChooserScreen extends StatelessWidget {
  const ScanChooserScreen({
    super.key,
    this.onBack,
    this.onReceipt,
    this.onBarcode,
    this.onByHand,
  });

  final VoidCallback? onBack;
  final VoidCallback? onReceipt;
  final VoidCallback? onBarcode;
  final VoidCallback? onByHand;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const SizedBox(height: 12),
              const ScreenTitle(
                ['Add to your', 'kitchen'],
                subtitle: 'Whichever is quickest for what you have in front '
                    'of you.',
              ),
              const SizedBox(height: 26),
              _Route(
                icon: Icons.receipt_long_outlined,
                title: 'Photograph a receipt',
                body: 'Reads the whole shop at once and works out expiry dates '
                    'for you.',
                badge: 'Fastest',
                onTap: onReceipt,
              ),
              const SizedBox(height: 14),
              _Route(
                icon: Icons.qr_code_scanner,
                title: 'Scan a barcode',
                body: 'One packaged item at a time. Remembers the product for '
                    'next time.',
                onTap: onBarcode,
              ),
              const SizedBox(height: 14),
              _Route(
                icon: Icons.edit_outlined,
                title: 'Add by hand',
                body: 'Loose vegetables, leftovers, or anything without a '
                    'label.',
                onTap: onByHand,
              ),
              const SizedBox(height: 24),
              const InfoStrip(
                'Receipts work best flat, in good light, with the whole slip '
                'in frame.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _Route extends StatelessWidget {
  const _Route({
    required this.icon,
    required this.title,
    required this.body,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 24,
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: T.tintMint,
                borderRadius: BorderRadius.circular(17),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 24, color: T.accentPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: T.cardSemiBold15)),
                      if (badge != null)
                        Pill(badge!,
                            fg: T.accentPrimary, bg: T.tintMint),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(body,
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );
}

// The camera chrome sits over a live feed, so its surfaces are derived from
// the one scrim token rather than a new literal colour: `overlay/scrim` is
// opaque by design, and these are the same hue at reduced alpha.
final _cameraChrome = T.overlayScrim.withValues(alpha: 0.55);
const _cameraBackdrop = T.overlayScrim;

// ------------------------------------------------------------------ 14

/// The camera screen. The viewfinder is supplied by the caller so this stays
/// renderable in a test and on a machine with no camera.
class ReceiptCameraScreen extends StatelessWidget {
  const ReceiptCameraScreen({
    super.key,
    this.viewfinder,
    this.onBack,
    this.onShutter,
    this.onGallery,
    this.torchOn = false,
    this.onToggleTorch,
  });

  final Widget? viewfinder;
  final VoidCallback? onBack;
  final VoidCallback? onShutter;
  final VoidCallback? onGallery;
  final bool torchOn;
  final VoidCallback? onToggleTorch;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _cameraBackdrop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            viewfinder ?? const ColoredBox(color: _cameraBackdrop),
            // The frame guide is the single most effective thing for OCR
            // quality: a receipt photographed at an angle parses badly, and no
            // amount of parser tuning recovers it.
            const _FrameGuide(),
            const CameraScrim(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _DarkCircle(
                            icon: Icons.arrow_back, onTap: onBack),
                        const Spacer(),
                        _DarkCircle(
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
                      color: _cameraChrome,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Lay the receipt flat and fit the whole slip inside the '
                      'frame.',
                      textAlign: TextAlign.center,
                      style: T.secondaryRegular13
                          .copyWith(color: T.textOnAccent),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _DarkCircle(
                          icon: Icons.photo_library_outlined,
                          onTap: onGallery),
                      _Shutter(onTap: onShutter),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 34),
                ],
              ),
            ),
          ],
        ),
      );
}

class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(34, 120, 34, 190),
          decoration: BoxDecoration(
            border: Border.all(color: T.textOnAccent, width: 2),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
}

class _DarkCircle extends StatelessWidget {
  const _DarkCircle({required this.icon, this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: active ? T.textOnAccent : _cameraChrome,
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

class _Shutter extends StatelessWidget {
  const _Shutter({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: T.textOnAccent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 74,
            height: 74,
            padding: const EdgeInsets.all(5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _cameraBackdrop, width: 2),
              ),
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------ 15

/// Reading the receipt. Named steps rather than a bare spinner: OCR takes a
/// few seconds, and a progress indicator that says what is happening is the
/// difference between waiting and wondering.
class ReadingReceiptScreen extends StatelessWidget {
  const ReadingReceiptScreen({
    super.key,
    required this.step,
    this.onCancel,
  });

  final ReadingStep step;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => AppScreen(
        scrollable: false,
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Spacer(),
              Center(
                child: ArtHalo(
                  size: 190,
                  child: Icon(Icons.receipt_long,
                      size: 88, color: T.accentPrimary),
                ),
              ),
              const SizedBox(height: 30),
              const ScreenTitle(['Reading your', 'receipt']),
              const SizedBox(height: 8),
              Text('This usually takes a few seconds.',
                  style:
                      T.secondaryRegular13.copyWith(color: T.textSecondary)),
              const SizedBox(height: 28),
              AppCard(
                child: Column(
                  children: [
                    for (final s in ReadingStep.values)
                      _StepRow(
                        label: s.label,
                        state: s.index < step.index
                            ? _StepState.done
                            : s.index == step.index
                                ? _StepState.active
                                : _StepState.pending,
                      ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              Center(
                child: TextButton(
                  onPressed: onCancel,
                  child: Text('Stop and go back',
                      style: T.labelMedium12
                          .copyWith(color: T.textSecondary)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

enum ReadingStep {
  reading('Reading the text'),
  matching('Matching to your catalogue'),
  estimating('Working out expiry dates');

  const ReadingStep(this.label);

  final String label;
}

enum _StepState { done, active, pending }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (state) {
      _StepState.done => (Icons.check_circle, T.accentPrimary),
      _StepState.active => (Icons.radio_button_checked, T.accentPrimary),
      _StepState.pending => (Icons.circle_outlined, T.structureBorder),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colour),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: state == _StepState.pending
                  ? T.bodyRegular14.copyWith(color: T.textSecondary)
                  : T.bodyRegular14,
            ),
          ),
          if (state == _StepState.active)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: T.accentPrimary),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 16, 17

/// Review and confirm. Screens 16 and 17 are the same screen: 17 is 16 with at
/// least one row needing input, which is a state rather than a destination.
class ReviewReceiptScreen extends StatelessWidget {
  const ReviewReceiptScreen({
    super.key,
    required this.receipt,
    required this.categoryOf,
    required this.glyphOf,
    this.onBack,
    this.onConfirm,
    this.onEditRow,
    this.onRemoveRow,
    this.suppressed = const [],
  });

  final ParsedReceipt receipt;

  /// Supplied by the caller so this screen holds no catalogue lookup of its
  /// own — the resolution already happened in the parser.
  final FoodCategory Function(ParsedItem) categoryOf;
  final String Function(ParsedItem) glyphOf;

  final VoidCallback? onBack;
  final VoidCallback? onConfirm;
  final ValueChanged<ParsedItem>? onEditRow;
  final ValueChanged<ParsedItem>? onRemoveRow;

  /// Things already in the kitchen, left off the shopping list. Named in the
  /// spec as screen 15's promise: "we have left them off".
  final List<String> suppressed;

  @override
  Widget build(BuildContext context) {
    final needsInput = receipt.needsInputCount;
    return AppScreen(
      child: Gutter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(onBack: onBack, title: 'Check the list'),
            const SizedBox(height: 12),
            ScreenTitle(
              [
                '${receipt.items.length} '
                    '${receipt.items.length == 1 ? 'thing' : 'things'} found',
              ],
              subtitle: needsInput == 0
                  ? 'Have a quick look, then add them to your kitchen.'
                  : needsInput == 1
                      ? 'One needs a moment from you — tap it to say what it '
                          'is.'
                      : '$needsInput need a moment from you — tap them to say '
                          'what they are.',
            ),
            const SizedBox(height: 20),
            if (needsInput > 0) ...[
              _NeedsInputStrip(count: needsInput),
              const SizedBox(height: 16),
            ],
            for (final item in receipt.items) ...[
              _ReviewRow(
                item: item,
                category: categoryOf(item),
                glyphKey: glyphOf(item),
                onEdit: () => onEditRow?.call(item),
                onRemove: () => onRemoveRow?.call(item),
              ),
              const SizedBox(height: 10),
            ],
            if (suppressed.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoStrip(
                'You already have ${_list(suppressed)} — we have left '
                '${suppressed.length == 1 ? 'it' : 'them'} off.',
                icon: Icons.check_circle_outline,
              ),
            ],
            if (receipt.skippedLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${receipt.skippedLines.length} lines skipped as not shopping '
                '(totals, tax, store details).',
                style: T.chipSemiBold11.copyWith(color: T.textSecondary),
              ),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: needsInput > 0
                  ? 'Add the ${receipt.items.length - needsInput} that are ready'
                  : 'Add ${receipt.items.length} to my kitchen',
              onPressed: onConfirm,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _list(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

class _NeedsInputStrip extends StatelessWidget {
  const _NeedsInputStrip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: T.stateAmberBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.help_outline, size: 19, color: T.stateAmberText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 1
                    ? 'One line was not clear enough to match. We would rather '
                        'ask than guess.'
                    : '$count lines were not clear enough to match. We would '
                        'rather ask than guess.',
                style:
                    T.secondaryRegular13.copyWith(color: T.stateAmberText),
              ),
            ),
          ],
        ),
      );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.item,
    required this.category,
    required this.glyphKey,
    this.onEdit,
    this.onRemove,
  });

  final ParsedItem item;
  final FoodCategory category;
  final String glyphKey;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onEdit,
        radius: 22,
        padding: const EdgeInsets.all(12),
        border: item.needsInput ? T.stateAmberText : null,
        child: Row(
          children: [
            item.needsInput
                ? Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: T.stateAmberBg,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.question_mark,
                        size: 22, color: T.stateAmberText),
                  )
                : ProduceTile(
                    glyphKey: glyphKey,
                    category: category,
                    size: 54,
                    radius: 17,
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The receipt's own wording, not the canonical name: the user
                  // recognises "AMUL TAAZA" from the slip in their hand.
                  Text(item.rawName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cardSemiBold15),
                  const SizedBox(height: 3),
                  Text(
                    item.needsInput
                        ? 'Tap to say what this is'
                        : _detail(item),
                    style: T.secondaryRegular13.copyWith(
                      color: item.needsInput
                          ? T.stateAmberText
                          : T.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              iconSize: 19,
              visualDensity: VisualDensity.compact,
              tooltip: 'Take off the list',
              icon: const Icon(Icons.close, color: T.textSecondary),
            ),
          ],
        ),
      );

  static String _detail(ParsedItem item) {
    final parts = <String>[
      if (item.canonicalName != null) item.canonicalName!,
      '${item.quantity}${item.unit == null ? '' : ' ${item.unit}'}',
      if (item.priceInr != null) '₹${item.priceInr!.toStringAsFixed(0)}',
    ];
    return parts.join(' · ');
  }
}

// ------------------------------------------------------------------ 18

class AddedSummaryScreen extends StatelessWidget {
  const AddedSummaryScreen({
    super.key,
    required this.addedCount,
    required this.soonestName,
    required this.soonestDays,
    this.onDone,
    this.onSeeKitchen,
    this.pendingCount = 0,
  });

  final int addedCount;
  final String soonestName;
  final int soonestDays;
  final VoidCallback? onDone;
  final VoidCallback? onSeeKitchen;

  /// Rows the user skipped rather than resolving. Stated, not hidden.
  final int pendingCount;

  @override
  Widget build(BuildContext context) => AppScreen(
        scrollable: false,
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Spacer(),
              Center(
                child: ArtHalo(
                  size: 200,
                  child: Icon(Icons.check_circle,
                      size: 96, color: T.accentPrimary),
                ),
              ),
              const SizedBox(height: 30),
              ScreenTitle([
                '$addedCount ${addedCount == 1 ? 'thing' : 'things'}',
                'added',
              ]),
              const SizedBox(height: 10),
              Text(
                soonestDays == 0
                    ? 'Your $soonestName is best used today — worth planning '
                        'around.'
                    : 'The soonest is your $soonestName, in $soonestDays '
                        '${soonestDays == 1 ? 'day' : 'days'}.',
                style: T.bodyRegular14.copyWith(color: T.textSecondary),
              ),
              if (pendingCount > 0) ...[
                const SizedBox(height: 20),
                InfoStrip(
                  '$pendingCount ${pendingCount == 1 ? 'line' : 'lines'} '
                  'left unresolved. You can add '
                  '${pendingCount == 1 ? 'it' : 'them'} by hand any time.',
                  icon: Icons.pending_outlined,
                ),
              ],
              const Spacer(flex: 2),
              AppButton(label: 'See my kitchen', onPressed: onSeeKitchen),
              const SizedBox(height: 12),
              AppButton.secondary(label: 'Add something else', onPressed: onDone),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------ 19

/// The receipt could not be read. Every route forward is offered, and the
/// reasons are specific enough to act on — "Warning: OCR failed" tells the
/// user nothing they can do.
class ReceiptUnreadableScreen extends StatelessWidget {
  const ReceiptUnreadableScreen({
    super.key,
    this.onRetake,
    this.onByHand,
    this.onBack,
  });

  final VoidCallback? onRetake;
  final VoidCallback? onByHand;
  final VoidCallback? onBack;

  static const _reasons = [
    'Photograph it flat — a curled slip blurs at the edges',
    'Get the whole receipt in frame, top to bottom',
    'Bright, even light, and avoid your own shadow',
    'Faded thermal print is often unreadable; adding by hand is quicker',
  ];

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const SizedBox(height: 20),
              Center(
                child: ArtHalo(
                  size: 170,
                  colour: T.tintPeach,
                  child: Icon(Icons.image_search,
                      size: 80, color: T.stateAmberText),
                ),
              ),
              const SizedBox(height: 26),
              const ScreenTitle(
                ['We could not', 'read that one'],
                subtitle: 'It happens. Here is what usually fixes it.',
              ),
              const SizedBox(height: 22),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final reason in _reasons)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb_outline,
                                size: 18, color: T.accentPrimary),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(reason, style: T.bodyRegular14)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              AppButton(label: 'Take another photo', onPressed: onRetake),
              const SizedBox(height: 12),
              AppButton.secondary(label: 'Add by hand instead', onPressed: onByHand),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}
