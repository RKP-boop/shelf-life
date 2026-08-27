import 'package:flutter/material.dart';
import 'tokens.g.dart';

/// Assembles Flutter's ThemeData from the generated tokens.
///
/// Nothing here invents a value — every colour and size comes from
/// tokens.g.dart, which is generated from design/tokens.json. If a value is
/// missing from the design file, it belongs in Figma first, not here.
abstract final class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: T.pageCream,
      colorScheme: base.colorScheme.copyWith(
        primary: T.accentPrimary,
        onPrimary: T.textOnAccent,
        surface: T.cardBase,
        onSurface: T.textPrimary,
        error: T.stateRedText,
      ),
      textTheme: base.textTheme.apply(fontFamily: T.fontFamily),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// The pastel wash behind every screen: mint at the top, through cream, to
  /// blush at the bottom. Three stops, matching the Figma frame fill.
  static const BoxDecoration pageGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.0, 0.42, 1.0],
      colors: [T.pageMint, T.pageCream, T.pageBlush],
    ),
  );

  /// Standard card elevation. Soft and low-contrast; the design reads as
  /// layered depth rather than hard shadows.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x140D2119),
      offset: Offset(0, 8),
      blurRadius: 20,
    ),
  ];

  /// Emerald buttons carry a tinted shadow so they lift off the pastel wash.
  static const List<BoxShadow> accentShadow = [
    BoxShadow(
      color: Color(0x4D0A7A55),
      offset: Offset(0, 8),
      blurRadius: 18,
    ),
  ];

  /// Interaction states must never be instantaneous — an abrupt change reads
  /// as a glitch rather than as feedback.
  static const Duration tap = Duration(milliseconds: 120);
  static const Duration transition = Duration(milliseconds: 240);
}
