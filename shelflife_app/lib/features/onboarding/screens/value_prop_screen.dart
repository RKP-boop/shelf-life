// Screens 01, 02, 03 — the three value props.
//
// D15: screen 01 in the source doc drew three page dots but only one value
// prop existed. Three dots is a promise of three screens, so there are three,
// each carrying one idea. One screen per idea also means the copy can be
// concrete instead of a feature list.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/produce_image.dart';

/// The content of one value prop. Held as data rather than three near-identical
/// widget trees, so the layout can only be wrong once.
class ValueProp {
  const ValueProp({
    required this.title,
    required this.body,
    required this.glyphKey,
    required this.halo,
  });

  final List<String> title;
  final String body;
  final String glyphKey;
  final Color halo;

  /// Ordered as the arc the user actually travels: the problem, the effort we
  /// remove, then the payoff.
  static const all = [
    ValueProp(
      title: ["Let's make your", "kitchen remember"],
      body: "What you bought, what is still good, and what to cook tonight.",
      // TODO(art): awaiting onboard-fridge.png from Figma. Using the spinach
      // render meanwhile so the screen does not regress to a placeholder.
      glyphKey: "spinach",
      halo: T.tintMint,
    ),
    ValueProp(
      title: ["Scan once.", "That is it."],
      body: "Photograph your receipt and your whole kitchen is logged in "
          "about forty seconds.",
      // TODO(art): awaiting onboard-receipt.png from Figma.
      glyphKey: "tomato",
      halo: T.tintPeach,
    ),
    ValueProp(
      title: ["Cook what is", "about to turn"],
      body: "Recipes are ranked by what you already have and what needs using "
          "first, so dinner decides itself.",
      glyphKey: "paneer",
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
                child: ProduceImage(glyphKey: prop.glyphKey, size: 184),
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
