// Golden tests. Tagged so CI can skip them.
//
// Golden images are font-rasterisation dependent: the same widget renders a
// few pixels differently on Linux than on Windows, so images committed from a
// Windows machine fail on an Ubuntu runner for reasons that have nothing to do
// with the code. Flutter's own guidance is to treat goldens as valid on one
// platform only. They run locally, where they were rendered.
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/engines/receipt_parser.dart';
import 'package:shelflife_app/features/capture/screens/barcode_screens.dart';
import 'package:shelflife_app/features/capture/screens/receipt_screens.dart';
import 'package:shelflife_app/features/dashboard/screens/home_states.dart';
import 'package:shelflife_app/models/enums.dart';

import 'fixtures.dart' as fx;
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // ------------------------------------------------------------ 09, 11, 12

  testWidgets('09 home empty', (tester) async {
    await pumpScreen(tester, const HomeEmptyScreen(greeting: 'Welcome, Rakesh'));
    await expectLater(find.byType(HomeEmptyScreen),
        matchesGoldenFile('goldens/09-home-empty.png'));
  });

  testWidgets('12 search with results', (tester) async {
    await pumpScreen(
      tester,
      SearchScreen(
        query: 'pan',
        results: fx.fullInventory
            .where((i) => i.productName.toLowerCase().contains('pan'))
            .toList(),
        onBack: _noop,
        today: fx.fixedToday,
      ),
    );
    await expectLater(find.byType(SearchScreen),
        matchesGoldenFile('goldens/12-search.png'));
  });

  testWidgets('12 search with no match', (tester) async {
    await pumpScreen(
      tester,
      SearchScreen(
        query: 'okra',
        results: const [],
        onBack: _noop,
        today: fx.fixedToday,
      ),
    );
    await expectLater(find.byType(SearchScreen),
        matchesGoldenFile('goldens/12-search-no-match.png'));
  });

  // ------------------------------------------------------------ 13–19

  testWidgets('13 scan chooser', (tester) async {
    await pumpScreen(tester, const ScanChooserScreen(onBack: _noop));
    await expectLater(find.byType(ScanChooserScreen),
        matchesGoldenFile('goldens/13-scan-chooser.png'));
  });

  testWidgets('14 receipt camera', (tester) async {
    await pumpScreen(tester, const ReceiptCameraScreen(onBack: _noop));
    await expectLater(find.byType(ReceiptCameraScreen),
        matchesGoldenFile('goldens/14-receipt-camera.png'));
  });

  testWidgets('15 reading receipt', (tester) async {
    await pumpScreen(
        tester, const ReadingReceiptScreen(step: ReadingStep.matching));
    await expectLater(find.byType(ReadingReceiptScreen),
        matchesGoldenFile('goldens/15-reading-receipt.png'));
  });

  testWidgets('16 review, everything matched', (tester) async {
    await pumpScreen(tester, _review(matched: true));
    await expectLater(find.byType(ReviewReceiptScreen),
        matchesGoldenFile('goldens/16-review.png'));
  });

  testWidgets('17 review, a row needs input', (tester) async {
    await pumpScreen(tester, _review(matched: false));
    await expectLater(find.byType(ReviewReceiptScreen),
        matchesGoldenFile('goldens/17-review-needs-input.png'));
  });

  testWidgets('18 added summary', (tester) async {
    await pumpScreen(
      tester,
      const AddedSummaryScreen(
        addedCount: 11,
        soonestName: 'spinach',
        soonestDays: 0,
        pendingCount: 1,
      ),
    );
    await expectLater(find.byType(AddedSummaryScreen),
        matchesGoldenFile('goldens/18-added-summary.png'));
  });

  testWidgets('19 receipt unreadable', (tester) async {
    await pumpScreen(tester, const ReceiptUnreadableScreen(onBack: _noop));
    await expectLater(find.byType(ReceiptUnreadableScreen),
        matchesGoldenFile('goldens/19-receipt-unreadable.png'));
  });

  // ------------------------------------------------------------ 20–23

  testWidgets('20 barcode scanner', (tester) async {
    await pumpScreen(tester, const BarcodeScannerScreen(onBack: _noop));
    await expectLater(find.byType(BarcodeScannerScreen),
        matchesGoldenFile('goldens/20-barcode-scanner.png'));
  });

  testWidgets('21 barcode found', (tester) async {
    await pumpScreen(
      tester,
      const BarcodeFoundScreen(
        productName: 'Amul Taaza',
        brand: 'Amul · Toned milk · 500 ml',
        category: FoodCategory.dairy,
        glyphKey: 'milk',
        barcode: '8901262010016',
        expiryLine: 'Best used by 30 August',
        expiryReason: 'Printed on the pack, so we are going with that.',
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(BarcodeFoundScreen),
        matchesGoldenFile('goldens/21-barcode-found.png'));
  });

  testWidgets('22 barcode not known', (tester) async {
    await pumpScreen(
      tester,
      const BarcodeUnknownScreen(barcode: '8901030612345', onBack: _noop),
    );
    await expectLater(find.byType(BarcodeUnknownScreen),
        matchesGoldenFile('goldens/22-barcode-unknown.png'));
  });

  testWidgets('23 add by hand', (tester) async {
    await pumpScreen(
      tester,
      const AddByHandScreen(
        onBack: _noop,
        prefilledName: 'Spin',
        suggestions: ['Spinach', 'Spring onion'],
        expiryPreview: 'We would say best used by 31 August',
        expiryReason: 'Fresh greens keep about three days in the fridge.',
      ),
    );
    await expectLater(find.byType(AddByHandScreen),
        matchesGoldenFile('goldens/23-add-by-hand.png'));
  });
}

ReviewReceiptScreen _review({required bool matched}) {
  final items = [
    ParsedItem(
        rawName: 'AMUL TAAZA TONED MILK 500ML',
        canonicalName: 'milk',
        quantity: 1,
        unit: 'L',
        priceInr: 34),
    ParsedItem(
        rawName: 'PALAK 250G',
        canonicalName: 'spinach',
        quantity: 250,
        unit: 'g',
        priceInr: 28),
    ParsedItem(
        rawName: 'TOMATO LOOSE',
        canonicalName: 'tomato',
        quantity: 1,
        unit: 'kg',
        priceInr: 46),
    if (!matched)
      ParsedItem(
          rawName: 'MTR RD BSN LDU 200',
          canonicalName: null,
          quantity: 1,
          priceInr: 95),
  ];
  return ReviewReceiptScreen(
    receipt: ParsedReceipt(
      items: items,
      skippedLines: const ['SUBTOTAL 203.00', 'CGST 2.5%', 'THANK YOU'],
    ),
    categoryOf: (item) => switch (item.canonicalName) {
      'milk' => FoodCategory.dairy,
      'spinach' || 'tomato' => FoodCategory.vegetables,
      _ => FoodCategory.other,
    },
    glyphOf: (item) => item.canonicalName ?? 'cat-pantry',
    suppressed: const ['onions', 'rice'],
    onBack: _noop,
  );
}

void _noop() {}
