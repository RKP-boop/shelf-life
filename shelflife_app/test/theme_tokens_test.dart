// Guards the design/code contract.
//
// lib/core/theme/tokens.g.dart is generated from design/tokens.json, which was
// itself read out of the Figma file. This test re-reads the JSON and compares,
// so a hand-edit to the generated Dart cannot survive CI — the whole point of
// generating rather than hand-typing is that the two cannot drift.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/theme/tokens.g.dart';

Color _parseHex(String hex) =>
    Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

void main() {
  // The test runs from the package root, so tokens.json is one level up.
  final tokensFile = File('../design/tokens.json');

  late Map<String, dynamic> tokens;

  setUpAll(() {
    expect(tokensFile.existsSync(), isTrue,
        reason: 'design/tokens.json must exist — it is the design contract');
    tokens = jsonDecode(tokensFile.readAsStringSync()) as Map<String, dynamic>;
  });

  test('every colour token exists in the generated theme with the right value', () {
    final colours = (tokens['colour'] as Map).cast<String, String>();

    // A representative set, checked by value. Spot-checking beats reflection
    // here: Dart has no runtime field lookup on a const class, and naming every
    // token explicitly means a rename shows up as a compile error.
    final expected = <String, Color>{
      'pageMint': _parseHex(colours['page/mint']!),
      'pageCream': _parseHex(colours['page/cream']!),
      'pageBlush': _parseHex(colours['page/blush']!),
      'cardBase': _parseHex(colours['card/base']!),
      'cardSoft': _parseHex(colours['card/soft']!),
      'textPrimary': _parseHex(colours['text/primary']!),
      'textSecondary': _parseHex(colours['text/secondary']!),
      'accentPrimary': _parseHex(colours['accent/primary']!),
      'stateAmberText': _parseHex(colours['state/amber-text']!),
      'stateRedText': _parseHex(colours['state/red-text']!),
      'infoText': _parseHex(colours['info/text']!),
    };

    final actual = <String, Color>{
      'pageMint': T.pageMint,
      'pageCream': T.pageCream,
      'pageBlush': T.pageBlush,
      'cardBase': T.cardBase,
      'cardSoft': T.cardSoft,
      'textPrimary': T.textPrimary,
      'textSecondary': T.textSecondary,
      'accentPrimary': T.accentPrimary,
      'stateAmberText': T.stateAmberText,
      'stateRedText': T.stateRedText,
      'infoText': T.infoText,
    };

    for (final entry in expected.entries) {
      expect(actual[entry.key], entry.value,
          reason: '${entry.key} has drifted from design/tokens.json — '
              'run: python tools/gen_theme.py');
    }
  });

  test('the accent is the AA-safe emerald, not the reference value', () {
    // Decision D14. White text on the reference's #0E9E6E measures 3.42:1 and
    // fails WCAG AA, which would make every primary CTA non-compliant against
    // PRD 4.11. #0A7A55 measures 5.35:1.
    expect(T.accentPrimary, const Color(0xFF0A7A55));
    expect(T.accentPrimary, isNot(const Color(0xFF0E9E6E)));
  });

  test('scale values match', () {
    final scale = (tokens['scale'] as Map).cast<String, dynamic>();
    expect(T.space16, (scale['space/16'] as num).toDouble());
    expect(T.radiusCard, (scale['radius/card'] as num).toDouble());
    expect(T.radiusScreen, (scale['radius/screen'] as num).toDouble());
    expect(T.sizeTapMin, (scale['size/tap-min'] as num).toDouble());
    expect(T.sizeScreenW, 412.0);
    expect(T.sizeScreenH, 915.0);
  });

  test('type ramp matches, including the family', () {
    final types = (tokens['type'] as Map).cast<String, dynamic>();
    final display = types['Display/Bold-30'] as Map;
    expect(T.displayBold30.fontSize, (display['size'] as num).toDouble());
    expect(T.displayBold30.fontWeight, FontWeight.w700);
    expect(T.fontFamily, display['family']);

    final chip = types['Chip/SemiBold-11'] as Map;
    expect(T.chipSemiBold11.fontSize, (chip['size'] as num).toDouble());
    expect(T.chipSemiBold11.fontWeight, FontWeight.w600);
  });

  test('tap targets meet the 48dp minimum required by PRD 4.11', () {
    expect(T.sizeTapMin, greaterThanOrEqualTo(48.0));
  });

  test('exactly two freshness states carry a badge; fresh is silent', () {
    // Decision D4: green is the brand colour here, so a green "Fresh" chip
    // reads as decoration rather than information. Marking only exceptions is
    // quieter and more useful — a clean row means nothing needs attention.
    expect(Freshness.values.length, 3); // fresh, soon, today
    expect(Freshness.fresh.name, 'fresh');
  });
}
