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
import 'package:shelflife_app/core/widgets/app_widgets.dart';
import 'package:shelflife_app/features/dashboard/screens/home_screen.dart';
import 'package:shelflife_app/models/enums.dart';

import 'fixtures.dart' as fx;
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('10 home', (tester) async {
    await pumpScreen(
      tester,
      HomeScreen(
        kitchenTitle: "Rakesh's kitchen",
        needsUsing: fx.needsUsing,
        suggestions: fx.suggestions,
        stats: fx.stats,
        shoppingCount: 5,
        today: fx.fixedToday,
      ),
    );
    await expectLater(
        find.byType(HomeScreen), matchesGoldenFile('goldens/10-home.png'));
  });

  testWidgets('10 home, nothing urgent', (tester) async {
    await pumpScreen(
      tester,
      HomeScreen(
        kitchenTitle: "Rakesh's kitchen",
        needsUsing: const [],
        suggestions: fx.suggestions.take(1).toList(),
        stats: fx.stats,
        shoppingCount: 0,
        today: fx.fixedToday,
      ),
    );
    await expectLater(find.byType(HomeScreen),
        matchesGoldenFile('goldens/10-home-clear.png'));
  });

  testWidgets('a fresh item shows no badge', (tester) async {
    await pumpScreen(
      tester,
      HomeScreen(
        kitchenTitle: "Rakesh's kitchen",
        needsUsing: [
          fx.item(
            name: 'Basmati rice',
            glyph: 'rice',
            category: FoodCategory.pantry,
            quantity: 5,
            unit: 'kg',
            daysLeft: 300,
          ),
        ],
        suggestions: const [],
        stats: fx.stats,
        shoppingCount: 0,
        today: fx.fixedToday,
      ),
    );
    // D4: fresh items carry no badge. A label reassuring the user that food is
    // fine is noise competing with the items that are not.
    expect(find.textContaining('Fresh'), findsNothing);
    expect(
      tester
          .widgetList<FreshnessBadge>(find.byType(FreshnessBadge))
          .where((b) => b.label != null),
      isEmpty,
    );
  });
}
