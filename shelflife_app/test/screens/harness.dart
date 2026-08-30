/// Renders a screen to a PNG at iPhone-14 logical size so it can be eyeballed.
///
/// Goldens here are a *review* tool as much as an assertion: the point is to
/// look at the image and compare it against the Figma frame. They are committed
/// so a later diff surfaces unintended visual change.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shelflife_app/core/theme/app_theme.dart';
import 'package:shelflife_app/core/theme/tokens.g.dart';

/// 390x844 is the iPhone 14 / Pixel 7 logical size the Figma frames use.
const previewSize = Size(390, 844);

const _weights = ['Regular', 'Medium', 'SemiBold', 'Bold'];

/// Loads the bundled Plus Jakarta Sans weights so goldens show real type.
///
/// The family name must match [T.fontFamily] exactly. When it does not, text
/// silently falls back to the test runner's placeholder font, whose glyphs are
/// all one em wide — which inflated every label and produced four bogus
/// overflow reports the first time this ran. [_assertRealFontLoaded] makes that
/// failure loud instead of plausible.
Future<void> loadAppFonts() async {
  final loader = FontLoader(T.fontFamily);
  for (final name in _weights) {
    final file = File('assets/fonts/PlusJakartaSans-$name.ttf');
    if (!file.existsSync()) {
      throw StateError('missing font ${file.path}; run from the package root');
    }
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  _assertRealFontLoaded();
  await _loadMaterialIcons();
}

/// Icons ship with the engine at runtime but not in the test asset bundle, so
/// without this every icon renders as an empty box and the goldens become
/// unreviewable.
///
/// The font is found by walking up from the running executable looking for the
/// SDK cache, rather than a fixed relative hop: under `flutter test` the
/// executable is the engine's flutter_tester, not the Dart SDK, and a fixed hop
/// silently resolved to a path that did not exist. Missing is skipped rather
/// than fatal — it makes the image uglier, not wrong.
Future<void> _loadMaterialIcons() async {
  File? found;
  for (var dir = File(Platform.resolvedExecutable).parent;
      dir.path != dir.parent.path;
      dir = dir.parent) {
    final candidate =
        File('${dir.path}/artifacts/material_fonts/materialicons-regular.otf');
    if (candidate.existsSync()) {
      found = candidate;
      break;
    }
  }
  if (found == null) {
    stderr.writeln('goldens: MaterialIcons font not found; icons will be boxes');
    return;
  }
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(found.readAsBytesSync().buffer)));
  await loader.load();
}

/// The placeholder test font advances exactly one em per glyph, so a four-glyph
/// string at 20px measures exactly 80.0. Any real font measures something else.
void _assertRealFontLoaded() {
  const probe = 'MMMM';
  const size = 20.0;
  final painter = TextPainter(
    text: const TextSpan(
      text: probe,
      style: TextStyle(fontFamily: T.fontFamily, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  if ((width - probe.length * size).abs() < 0.01) {
    throw StateError(
      'font "${T.fontFamily}" did not load: "$probe" measured ${width}px, '
      'the placeholder one-em-per-glyph advance. Goldens rendered now '
      'would show wrong metrics.',
    );
  }
}

/// Pumps [child] inside the real app theme at [previewSize].
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Size size = previewSize,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      // Pin the text scale: a golden that moves with the host
      // accessibility settings is not reproducible.
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: child,
    ),
  ));
  // Image.asset resolves asynchronously; without this the goldens show gaps.
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
  await tester.pump();
}
