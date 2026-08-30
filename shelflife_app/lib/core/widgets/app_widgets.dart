/// The shared widget library, mirroring the Figma components.
///
/// Built before the screens deliberately: with these right, 52 screens are
/// composition rather than 52 bespoke layouts, and a design change lands in one
/// place instead of fifty.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.g.dart';

// ------------------------------------------------------------ page scaffold

/// Every screen sits on the pastel wash with a 42dp device radius, matching
/// the Figma frames.
/// The 24dp page gutter from the Figma frames.
///
/// Applied per section rather than as one outer Padding, because horizontally
/// scrolling rows must bleed to the screen edge: a card clipped by the viewport
/// signals "there is more here", where a card clipped by a gutter just looks
/// broken.
class Gutter extends StatelessWidget {
  const Gutter({super.key, required this.child});

  static const width = 24.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: width),
        child: child,
      );
}

/// Gradient scrims behind camera chrome.
///
/// A camera preview can be any brightness, and white icons over a pale receipt
/// or a sunlit worktop become unreadable. These darken only the top and bottom
/// strips where the controls sit, so the middle of the frame — the part the
/// user is actually aiming — stays untouched.
class CameraScrim extends StatelessWidget {
  const CameraScrim({super.key, this.top = 190, this.bottom = 300});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Column(
          children: [
            _band(top, [
              T.overlayScrim.withValues(alpha: 0.55),
              T.overlayScrim.withValues(alpha: 0),
            ]),
            const Spacer(),
            _band(bottom, [
              T.overlayScrim.withValues(alpha: 0),
              T.overlayScrim.withValues(alpha: 0.65),
            ]),
          ],
        ),
      );

  static Widget _band(double height, List<Color> colours) => Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colours,
          ),
        ),
      );
}

/// Back arrow, optional centred title, optional trailing action.
///
/// The back affordance is a 44dp circle rather than a bare glyph so it clears
/// the 48dp row height with its padding, and reads as a control on the pastel
/// canvas where a floating chevron would not.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    this.onBack,
    this.title,
    this.trailing,
    this.trailingIcon,
    this.onTrailing,
  });

  final VoidCallback? onBack;
  final String? title;
  final Widget? trailing;
  final IconData? trailingIcon;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Row(
          children: [
            if (onBack != null)
              CircleIconButton(icon: Icons.arrow_back, onPressed: onBack)
            else
              const SizedBox(width: 44),
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: T.titleSemiBold18,
                    ),
            ),
            if (trailing != null)
              trailing!
            else if (trailingIcon != null)
              CircleIconButton(icon: trailingIcon!, onPressed: onTrailing)
            else
              const SizedBox(width: 44),
          ],
        ),
      );
}

/// Carousel position. The active dot is a stadium rather than a larger circle,
/// so position is conveyed by shape as well as opacity.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? T.accentPrimary : T.structureBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ],
      );
}

/// Circular halo behind a hero render. The soft ring is what makes a flat PNG
/// read as a lit object rather than a sticker.
class ArtHalo extends StatelessWidget {
  const ArtHalo({
    super.key,
    required this.child,
    this.size = 210,
    this.colour,
  });

  final Widget child;
  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colour ?? T.tintMint,
                    (colour ?? T.tintMint).withValues(alpha: 0),
                  ],
                  stops: const [0.55, 1],
                ),
              ),
            ),
            child,
          ],
        ),
      );
}

class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.child,
    this.bottomBar,
    this.floating,
    this.scrollable = true,
  });

  final Widget child;
  final Widget? bottomBar;
  final Widget? floating;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: EdgeInsets.only(bottom: bottomBar == null ? 0 : 112),
      child: child,
    );
    return DecoratedBox(
      decoration: AppTheme.pageGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          // StackFit.expand, not the default. A Stack sizes to its tallest
          // non-positioned child, so on a screen with little content the whole
          // Stack shrank and the bottom bar — positioned at its bottom — floated
          // partway up the page. Expanding pins the bar to the viewport and
          // lets the scroll view fill and scroll only when it needs to.
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (scrollable)
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: body,
                )
              else
                body,
              if (bottomBar != null)
                Positioned(left: 0, right: 0, bottom: 0, child: bottomBar!),
              ?floating,
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- surfaces

/// The standard white card: 24dp radius, soft low shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.colour,
    this.onTap,
    this.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? colour;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colour ?? T.cardBase,
        borderRadius: shape,
        boxShadow: AppTheme.cardShadow,
        border: border == null ? null : Border.all(color: border!, width: 1.4),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          // A non-zero duration matters: an instant state change reads as a
          // glitch rather than as feedback.
          splashColor: T.accentPrimary.withValues(alpha: 0.06),
          highlightColor: T.accentPrimary.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Blue informational strip. Blue is informational ONLY and never signals
/// urgency (PRD 4.12).
class InfoStrip extends StatelessWidget {
  const InfoStrip(this.text, {super.key, this.icon = Icons.lightbulb_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: T.infoBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: T.infoText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: T.secondaryRegular13.copyWith(color: T.infoText)),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------- badges

/// Freshness badge. Returns an empty widget for fresh items.
///
/// D4: green is the brand colour here, so a green "Fresh" chip would read as
/// decoration rather than information. Marking only the exceptions is quieter
/// and more useful — a clean row means nothing needs attention.
class FreshnessBadge extends StatelessWidget {
  const FreshnessBadge({super.key, required this.freshness, required this.label});

  final Freshness freshness;

  /// Null for fresh. Comes straight from ExpiryEstimator.badgeLabel.
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (freshness == Freshness.fresh || label == null) {
      return const SizedBox.shrink();
    }
    final isToday = freshness == Freshness.today;
    final fg = isToday ? T.stateRedText : T.stateAmberText;
    final bg = isToday ? T.stateRedBg : T.stateAmberBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A dot as well as colour: urgency must never be conveyed by colour
          // alone (PRD 4.11).
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          // Flexible, not bare Text: the badge sits on cards as narrow as
          // 120dp and a long label must ellipsize rather than overflow.
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.chipSemiBold11.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small pill for counts, times and categories. Interactive filters use
/// [FilterPill] instead — badges convey state, chips convey a selectable value,
/// and conflating them is a real anti-pattern.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.fg, this.bg, this.icon});

  final String label;
  final Color? fg;
  final Color? bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: bg ?? T.tintMint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg ?? T.accentPrimary),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: T.chipSemiBold11.copyWith(color: fg ?? T.accentPrimary)),
          ],
        ),
      );
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? T.accentPrimary : T.cardBase,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            // Sized by padding alone, deliberately. An `alignment` here makes
            // the Container expand to its incoming constraints, and inside a
            // Wrap those are bounded by the row width — which turned every
            // filter pill into a full-width bar.
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: selected
                  ? null
                  : Border.all(color: T.structureBorder, width: 1.2),
            ),
            child: Text(
              label,
              style: T.chipSemiBold11.copyWith(
                color: selected ? T.textOnAccent : T.textSecondary,
              ),
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------ buttons

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.trailingArrow = false,
    this.expand = true,
    this.danger = false,
  }) : _secondary = false;

  /// Outlined, quieter variant. Deliberately quieter than the filled button —
  /// equal visual weight between the two is the single most likely regression
  /// on the auth screen.
  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.expand = true,
  })  : trailingArrow = false,
        danger = false,
        _secondary = true;

  final String label;
  final VoidCallback? onPressed;
  final bool trailingArrow;
  final bool expand;
  final bool danger;
  final bool _secondary;

  @override
  Widget build(BuildContext context) {
    // A null callback means disabled, and it has to be visible. A full-colour
    // primary button that silently does nothing when tapped reads as the app
    // being broken — the user has no way to know the form is incomplete.
    final enabled = onPressed != null;

    final baseBg = _secondary
        ? T.cardBase
        : danger
            ? T.stateRedText
            : T.accentPrimary;
    final bg = enabled ? baseBg : T.cardSoft;
    final fg = enabled
        ? (_secondary ? T.textPrimary : T.textOnAccent)
        : T.textSecondary;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: T.cardSemiBold15.copyWith(color: fg)),
        if (trailingArrow) ...[
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
                color: T.cardBase, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_forward,
                size: 18, color: T.accentPrimary),
          ),
        ],
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: _secondary || !enabled ? null : AppTheme.accentShadow,
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 54,
            padding: EdgeInsets.symmetric(
                horizontal: trailingArrow ? 10 : 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: _secondary
                  ? Border.all(color: T.structureBorder, width: 1.4)
                  : null,
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Circular icon button on a white disc — back arrows, favourites, close.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.colour,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? colour;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: AppTheme.cardShadow,
        ),
        child: Material(
          color: T.cardBase,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: 21, color: colour ?? T.textPrimary),
            ),
          ),
        ),
      );
}

/// Quantity stepper. Both controls are 32dp inside a 48dp row.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    this.onChanged,
    this.min = 1,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: T.cardSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: T.structureBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _round(Icons.remove,
                value > min ? () => onChanged?.call(value - 1) : null),
            SizedBox(
              width: 34,
              child: Text('$value',
                  textAlign: TextAlign.center, style: T.cardSemiBold15),
            ),
            _round(Icons.add, () => onChanged?.call(value + 1)),
          ],
        ),
      );

  Widget _round(IconData icon, VoidCallback? onTap) => Material(
        color: onTap == null ? T.cardSoft : T.cardBase,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon,
                size: 17,
                color: onTap == null ? T.structureBorder : T.textPrimary),
          ),
        ),
      );
}

// ------------------------------------------------------------------- fields

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.focused = false,
    this.helper,
  });

  /// Always visible. A placeholder-only label is a known accessibility failure
  /// — it vanishes the moment the user types (PRD 4.11).
  final String label;

  final String? hint;
  final TextEditingController? controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool focused;
  final String? helper;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: T.labelMedium12.copyWith(color: T.textSecondary)),
          const SizedBox(height: 7),
          Container(
            decoration: BoxDecoration(
              color: T.cardBase,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: focused ? T.accentPrimary : T.structureBorder,
                width: focused ? 1.5 : 1.2,
              ),
            ),
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: T.bodyRegular14.copyWith(color: T.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: T.bodyRegular14.copyWith(color: T.textSecondary),
                prefixIcon: icon == null
                    ? null
                    : Icon(icon, size: 19, color: T.textSecondary),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper!,
                style: T.labelMedium12.copyWith(color: T.textSecondary)),
          ],
        ],
      );
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.hint = 'Search your kitchen',
    this.controller,
    this.onChanged,
    this.onFilterTap,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Container(
        height: 50,
        decoration: BoxDecoration(
          color: T.cardBase,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: T.structureBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search, size: 19, color: T.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                onChanged: onChanged,
                style: T.bodyRegular14.copyWith(color: T.textPrimary),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      T.bodyRegular14.copyWith(color: T.textSecondary),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (onFilterTap != null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Material(
                  color: T.accentPrimary,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: onFilterTap,
                    borderRadius: BorderRadius.circular(14),
                    child: const SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(Icons.tune, size: 19, color: T.textOnAccent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ section

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: T.sectionSemiBold16)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!,
                  style: T.labelMedium12.copyWith(color: T.accentPrimary)),
            ),
        ],
      );
}

/// Screen title in the two-size display ramp, with an optional subtitle.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.lines, {super.key, this.subtitle});

  final List<String> lines;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines) Text(line, style: T.displayBold26),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: T.secondaryRegular13.copyWith(color: T.textSecondary)),
          ],
        ],
      );
}

/// Empty state: halo, artwork, message, action. Used by all six empty screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    required this.artwork,
    this.action,
    this.onAction,
    this.haloColour,
  });

  final String title;
  final String body;
  final Widget artwork;
  final String? action;
  final VoidCallback? onAction;
  final Color? haloColour;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        radius: 28,
        child: Column(
          children: [
            SizedBox(
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 164,
                    height: 164,
                    decoration: BoxDecoration(
                      color: haloColour ?? T.tintMint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  artwork,
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: T.sectionSemiBold16),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: T.bodyRegular14.copyWith(color: T.textSecondary)),
            if (action != null) ...[
              const SizedBox(height: 22),
              AppButton(label: action!, onPressed: onAction),
            ],
          ],
        ),
      );
}
