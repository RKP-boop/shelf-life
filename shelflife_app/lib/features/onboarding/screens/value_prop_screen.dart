// Screens 01, 02, 03 — the three value props.
//
// D15: screen 01 in the source doc drew three page dots but only one value
// prop existed. Three dots is a promise of three screens, so there are three,
// each carrying one idea. One screen per idea also means the copy can be
// concrete instead of a feature list.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';

/// The content of one value prop. Held as data rather than three near-identical
/// widget trees, so the layout can only be wrong once.
class ValueProp {
  const ValueProp({
    required this.title,
    required this.body,
    required this.artAsset,
    required this.halo,
  });

  final List<String> title;
  final String body;

  /// A full asset path rather than a produce glyph key.
  ///
  /// The onboarding art is hero illustration, not a catalogue glyph: it has its
  /// own aspect ratio, is shown far larger than any produce tile, and ships as
  /// WebP because these are photographic renders that PNG compresses badly —
  /// the fridge is 123 KB as WebP against 654 KB as PNG, with no visible
  /// difference. Reusing ProduceImage here would have meant teaching the glyph
  /// resolver about file extensions it otherwise never needs.
  final String artAsset;

  final Color halo;

  /// Ordered as the arc the user actually travels: the problem, the effort we
  /// remove, then the payoff.
  static const all = [
    ValueProp(
      title: ["Let's make your", "kitchen remember"],
      body: "What you bought, what is still good, and what to cook tonight.",
      artAsset: "assets/onboarding/fridge.webp",
      halo: T.tintMint,
    ),
    ValueProp(
      title: ["Scan once.", "That is it."],
      body: "Photograph your receipt and your whole kitchen is logged in "
          "about forty seconds.",
      artAsset: "assets/onboarding/receipt.webp",
      halo: T.tintPeach,
    ),
    ValueProp(
      title: ["Cook what is", "about to turn"],
      body: "Recipes are ranked by what you already have and what needs using "
          "first, so dinner decides itself.",
      artAsset: "assets/produce/paneer.png",
      halo: T.tintLemon,
    ),
  ];
}

class ValuePropScreen extends StatelessWidget {
  const ValuePropScreen({
    super.key,
    required this.index,
    this.onNext,
    this.onSkip,
  });

  final int index;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final prop = ValueProp.all[index];
    final isLast = index == ValueProp.all.length - 1;

    return AppScreen(
      scrollable: false,
      child: Gutter(
        child: Column(
          // Left-aligned throughout. A centred title over left-aligned body
          // copy reads as an accident, and the rest of the app is left-aligned.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Skip stays available on every card. Forcing three taps
                  // before the product is usable is the thing onboarding is
                  // most often criticised for.
                  TextButton(
                    onPressed: onSkip,
                    child: Text('Skip',
                        style: T.labelMedium12
                            .copyWith(color: T.textSecondary)),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            Center(
              child: ArtHalo(
                size: 250,
                colour: prop.halo,
                // Sized by height, not a square box: the fridge is nearly
                // square and the receipt is tall, and constraining both to the
                // same height gives them equal presence as the user pages
                // through. contain keeps each undistorted.
                child: SizedBox(
                  height: 212,
                  child: Image.asset(
                    prop.artAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.eco_outlined,
                      size: 84,
                      color: T.accentPrimary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 3),
            ScreenTitle(prop.title),
            const SizedBox(height: 12),
            Text(
              prop.body,
              style: T.bodyRegular14.copyWith(color: T.textSecondary),
            ),
            const Spacer(flex: 2),
            Center(
              child: PageDots(
                  count: ValueProp.all.length, index: index),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: isLast ? 'Get started' : 'Next',
              trailingArrow: !isLast,
              onPressed: onNext,
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
