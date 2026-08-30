// Golden tests. Tagged so CI can skip them.
//
// Golden images are font-rasterisation dependent: the same widget renders a
// few pixels differently on Linux than on Windows, so images committed from a
// Windows machine fail on an Ubuntu runner for reasons that have nothing to do
// with the code. Flutter's own guidance is to treat goldens as valid on one
// platform only. They run locally, where they were rendered.
@Tags(['golden'])
library;

// Goldens for groups 3.5 through 3.10 — screens 24–52.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/engines/recipe_scorer.dart';
import 'package:shelflife_app/features/inventory/screens/inventory_screen.dart';
import 'package:shelflife_app/features/inventory/screens/item_screens.dart';
import 'package:shelflife_app/features/notifications/screens/notification_screens.dart';
import 'package:shelflife_app/features/profile/screens/profile_screens.dart';
import 'package:shelflife_app/features/recipes/screens/recipe_screens.dart';
import 'package:shelflife_app/features/shopping/screens/shopping_screens.dart';
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/models/models.dart';

import 'fixtures.dart' as fx;
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // ------------------------------------------------------- 24–28, 32

  testWidgets('24 inventory, everything', (tester) async {
    await pumpScreen(
      tester,
      InventoryScreen(items: fx.fullInventory, today: fx.fixedToday),
    );
    await expectLater(find.byType(InventoryScreen),
        matchesGoldenFile('goldens/24-inventory.png'));
  });

  testWidgets('25 inventory, by kind', (tester) async {
    await pumpScreen(
      tester,
      InventoryScreen(
        items: fx.fullInventory,
        grouping: InventoryGrouping.category,
        today: fx.fixedToday,
      ),
    );
    await expectLater(find.byType(InventoryScreen),
        matchesGoldenFile('goldens/25-inventory-by-kind.png'));
  });

  testWidgets('26 inventory, by where it is', (tester) async {
    await pumpScreen(
      tester,
      InventoryScreen(
        items: fx.fullInventory,
        grouping: InventoryGrouping.storage,
        today: fx.fixedToday,
      ),
    );
    await expectLater(find.byType(InventoryScreen),
        matchesGoldenFile('goldens/26-inventory-by-place.png'));
  });

  testWidgets('27 sort and filter sheet', (tester) async {
    await pumpScreen(
      tester,
      const _Sheet(
          child: InventoryFilterSheet(sort: InventorySort.soonestFirst)),
    );
    await expectLater(find.byType(InventoryFilterSheet),
        matchesGoldenFile('goldens/27-filter-sheet.png'));
  });

  testWidgets('28 inventory empty', (tester) async {
    await pumpScreen(
      tester,
      InventoryScreen(items: const [], today: fx.fixedToday),
    );
    await expectLater(find.byType(InventoryScreen),
        matchesGoldenFile('goldens/28-inventory-empty.png'));
  });

  // ------------------------------------------------------------ 29–31

  testWidgets('29 item detail', (tester) async {
    await pumpScreen(
      tester,
      ItemDetailScreen(
        item: fx.needsUsing.first,
        expiryLine: 'Best used today',
        recipeSuggestions: const [
          (
            name: 'Palak paneer',
            matchLabel: '6 of 7 ingredients',
            imageKey: 'palak-paneer'
          ),
          (
            name: 'Paneer bhurji',
            matchLabel: 'all 6 ingredients',
            imageKey: 'paneer-bhurji'
          ),
        ],
        onBack: _noop,
        today: fx.fixedToday,
      ),
    );
    await expectLater(find.byType(ItemDetailScreen),
        matchesGoldenFile('goldens/29-item-detail.png'));
  });

  testWidgets('30 edit item', (tester) async {
    await pumpScreen(
      tester,
      EditItemScreen(
        item: fx.needsUsing.first,
        expiryLabel: '28 August',
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(EditItemScreen),
        matchesGoldenFile('goldens/30-edit-item.png'));
  });

  testWidgets('31 remove item sheet', (tester) async {
    await pumpScreen(
      tester,
      _Sheet(child: RemoveItemSheet(item: fx.needsUsing.first)),
    );
    await expectLater(find.byType(RemoveItemSheet),
        matchesGoldenFile('goldens/31-remove-item.png'));
  });

  // ------------------------------------------------------------ 33–38

  testWidgets('33 recipes', (tester) async {
    await pumpScreen(
      tester,
      RecipesScreen(
          matches: fx.suggestions, filter: RecipeFilter.everything),
    );
    await expectLater(find.byType(RecipesScreen),
        matchesGoldenFile('goldens/33-recipes.png'));
  });

  testWidgets('34 recipe detail', (tester) async {
    await pumpScreen(tester, _detail(fx.suggestions.first));
    await expectLater(find.byType(RecipeDetailScreen),
        matchesGoldenFile('goldens/34-recipe-detail.png'));
  });

  testWidgets('35 recipe method', (tester) async {
    await pumpScreen(
      tester,
      const RecipeMethodScreen(
        name: 'Palak paneer',
        currentStep: 1,
        steps: [
          'Blanch the spinach for two minutes, then drop it into cold water so '
              'it keeps its colour.',
          'Blend to a smooth purée with the ginger, garlic and green chilli.',
          'Fry the onion until golden, add the tomato, and cook until it comes '
              'together.',
          'Stir in the purée, season, and simmer for five minutes.',
          'Add the paneer cubes and a spoon of cream. Take it off the heat.',
        ],
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(RecipeMethodScreen),
        matchesGoldenFile('goldens/35-recipe-method.png'));
  });

  testWidgets('36 cooked it', (tester) async {
    await pumpScreen(
      tester,
      const CookedItScreen(
        recipeName: 'Palak paneer',
        onBack: _noop,
        used: [
          CookedItem(
              id: '1',
              name: 'Spinach',
              amount: '250 g',
              glyphKey: 'spinach',
              urgent: true),
          CookedItem(
              id: '2',
              name: 'Paneer',
              amount: '200 g',
              glyphKey: 'paneer',
              urgent: true),
          CookedItem(
              id: '3', name: 'Onions', amount: '1', glyphKey: 'onion'),
          CookedItem(
              id: '4', name: 'Tomatoes', amount: '2', glyphKey: 'tomato'),
        ],
      ),
    );
    await expectLater(find.byType(CookedItScreen),
        matchesGoldenFile('goldens/36-cooked-it.png'));
  });

  testWidgets('37 recipes empty', (tester) async {
    await pumpScreen(
      tester,
      const RecipesScreen(matches: [], filter: RecipeFilter.canCookNow),
    );
    await expectLater(find.byType(RecipesScreen),
        matchesGoldenFile('goldens/37-recipes-empty.png'));
  });

  testWidgets('38 recipe with missing ingredients', (tester) async {
    await pumpScreen(tester, _detail(fx.suggestions.last));
    await expectLater(find.byType(RecipeDetailScreen),
        matchesGoldenFile('goldens/38-recipe-missing.png'));
  });

  // ------------------------------------------------------------ 39–41

  testWidgets('39 shopping list', (tester) async {
    await pumpScreen(
      tester,
      ShoppingListScreen(
        items: _shopping,
        onBack: _noop,
        glyphOf: (i) => i.ingredientId ?? 'cat-pantry',
      ),
    );
    await expectLater(find.byType(ShoppingListScreen),
        matchesGoldenFile('goldens/39-shopping-list.png'));
  });

  testWidgets('40 add to list', (tester) async {
    await pumpScreen(
      tester,
      const AddToListScreen(
        onBack: _noop,
        suggestions: ['Milk', 'Coriander', 'Curd', 'Atta'],
      ),
    );
    await expectLater(find.byType(AddToListScreen),
        matchesGoldenFile('goldens/40-add-to-list.png'));
  });

  testWidgets('41 shopping list empty', (tester) async {
    await pumpScreen(
      tester,
      const ShoppingListScreen(items: [], onBack: _noop),
    );
    await expectLater(find.byType(ShoppingListScreen),
        matchesGoldenFile('goldens/41-shopping-empty.png'));
  });

  // ------------------------------------------------------------ 42–47

  testWidgets('42 profile', (tester) async {
    await pumpScreen(
      tester,
      const ProfileScreen(
        displayName: 'Rakesh',
        email: 'rakesh@example.com',
        stats: fx.stats,
        syncState: SyncState.synced,
      ),
    );
    await expectLater(find.byType(ProfileScreen),
        matchesGoldenFile('goldens/42-profile.png'));
  });

  testWidgets('43 impact', (tester) async {
    await pumpScreen(
      tester,
      const ImpactScreen(
        stats: fx.stats,
        monthLabel: 'August so far',
        onBack: _noop,
        recentRescues: [
          (name: 'Spinach', when: 'Tuesday', glyphKey: 'spinach'),
          (name: 'Curd', when: 'Monday', glyphKey: 'curd'),
          (name: 'Bananas', when: 'Sunday', glyphKey: 'banana'),
        ],
      ),
    );
    await expectLater(find.byType(ImpactScreen),
        matchesGoldenFile('goldens/43-impact.png'));
  });

  testWidgets('44 reminders', (tester) async {
    await pumpScreen(
      tester,
      const RemindersScreen(
        enabled: true,
        threeDay: true,
        oneDay: true,
        sameDay: true,
        quietHours: '9 pm to 8 am',
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(RemindersScreen),
        matchesGoldenFile('goldens/44-reminders.png'));
  });

  testWidgets('44 reminders without permission', (tester) async {
    await pumpScreen(
      tester,
      const RemindersScreen(
        enabled: false,
        threeDay: true,
        oneDay: true,
        sameDay: true,
        quietHours: '9 pm to 8 am',
        permissionGranted: false,
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(RemindersScreen),
        matchesGoldenFile('goldens/44-reminders-no-permission.png'));
  });

  testWidgets('45 account', (tester) async {
    await pumpScreen(
      tester,
      const AccountScreen(
        email: 'rakesh@example.com',
        memberSince: 'August 2026',
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(AccountScreen),
        matchesGoldenFile('goldens/45-account.png'));
  });

  testWidgets('46 about', (tester) async {
    await pumpScreen(tester, const AboutScreen(version: '1.0.0', onBack: _noop));
    await expectLater(find.byType(AboutScreen),
        matchesGoldenFile('goldens/46-about.png'));
  });

  testWidgets('47 sign out with unsynced changes', (tester) async {
    await pumpScreen(tester, const _Sheet(child: SignOutSheet(pendingCount: 3)));
    await expectLater(find.byType(SignOutSheet),
        matchesGoldenFile('goldens/47-sign-out.png'));
  });

  // ------------------------------------------------------------ 48–52

  testWidgets('48 notification permission', (tester) async {
    await pumpScreen(
      tester,
      const NotificationPermissionScreen(
        firstItemName: 'spinach',
        firstItemDays: 2,
        glyphKey: 'spinach',
      ),
    );
    await expectLater(find.byType(NotificationPermissionScreen),
        matchesGoldenFile('goldens/48-notification-permission.png'));
  });

  testWidgets('49 reminders list', (tester) async {
    await pumpScreen(
      tester,
      const NotificationsScreen(
        onBack: _noop,
        entries: [
          NotificationEntry(
            id: '1',
            itemName: 'Spinach',
            level: NotificationLevel.sameDay,
            detail: 'Best used today — you have 250 g',
            glyphKey: 'spinach',
            category: FoodCategory.vegetables,
          ),
          NotificationEntry(
            id: '2',
            itemName: 'Paneer',
            level: NotificationLevel.sameDay,
            detail: 'Best used today — you have 200 g',
            glyphKey: 'paneer',
            category: FoodCategory.dairy,
          ),
          NotificationEntry(
            id: '3',
            itemName: 'Coriander',
            level: NotificationLevel.oneDay,
            detail: 'Tomorrow is its last good day',
            glyphKey: 'coriander',
            category: FoodCategory.vegetables,
          ),
          NotificationEntry(
            id: '4',
            itemName: 'Amul Taaza',
            level: NotificationLevel.threeDay,
            detail: 'Three days left',
            glyphKey: 'milk',
            category: FoodCategory.dairy,
          ),
        ],
      ),
    );
    await expectLater(find.byType(NotificationsScreen),
        matchesGoldenFile('goldens/49-reminders-list.png'));
  });

  testWidgets('50 offline', (tester) async {
    await pumpScreen(
      tester,
      const SyncStatusScreen(
        state: SyncState.offline,
        pendingCount: 4,
        lastSyncedLabel: '2 hours ago',
        oldestPendingLabel: 'a spinach edit, 40 minutes ago',
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(SyncStatusScreen),
        matchesGoldenFile('goldens/50-offline.png'));
  });

  testWidgets('51 syncing, with exhausted entries', (tester) async {
    await pumpScreen(
      tester,
      const SyncStatusScreen(
        state: SyncState.syncing,
        pendingCount: 2,
        lastSyncedLabel: 'just now',
        exhaustedCount: 1,
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(SyncStatusScreen),
        matchesGoldenFile('goldens/51-syncing.png'));
  });

  testWidgets('52 something did not go through', (tester) async {
    await pumpScreen(
      tester,
      const SomethingWrongScreen(
        what: 'We could not reach the server just now, so your last change is '
            'still sitting on this phone.',
        stillWorks: 'Everything in the app works as normal. Your change will '
            'go up on its own once you are back online.',
        detail: 'POST /rest/v1/inventory_items — no response after 10s',
        onBack: _noop,
      ),
    );
    await expectLater(find.byType(SomethingWrongScreen),
        matchesGoldenFile('goldens/52-something-wrong.png'));
  });
}

RecipeDetailScreen _detail(RecipeMatch match) => RecipeDetailScreen(
      match: match,
      servings: 4,
      onBack: _noop,
      ingredients: [
        for (final name in match.haveNames)
          IngredientLine(
            name: _title(name),
            amount: _amount(name),
            have: true,
            urgent: match.urgentNames.contains(name),
          ),
        for (final name in match.missingNames)
          IngredientLine(
            name: _title(name),
            amount: _amount(name),
            have: false,
          ),
        const IngredientLine(
            name: 'Green chilli', amount: '1', have: false, optional: true),
      ],
    );

String _title(String s) => s[0].toUpperCase() + s.substring(1);

String _amount(String name) => switch (name) {
      'spinach' => '500 g',
      'paneer' => '200 g',
      'onion' => '1 large',
      'tomato' => '2',
      'ginger' => '1 inch',
      'garlic' => '4 cloves',
      'cream' => '2 tbsp',
      'cauliflower' => '1 small',
      'potato' => '2',
      'coriander' => 'a handful',
      'capsicum' => '1',
      'atta' => '2 cups',
      _ => 'to taste',
    };

final _shopping = [
  ShoppingListItem(
    id: '1',
    userId: 'u1',
    productName: 'Cream',
    ingredientId: 'cream',
    quantity: 200,
    unit: 'ml',
    source: ShoppingSource.recipe,
    sourceRecipeName: 'Palak paneer',
    createdAt: fx.fixedToday,
  ),
  ShoppingListItem(
    id: '2',
    userId: 'u1',
    productName: 'Cauliflower',
    ingredientId: 'cauliflower',
    quantity: 1,
    source: ShoppingSource.recipe,
    sourceRecipeName: 'Aloo gobi',
    createdAt: fx.fixedToday,
  ),
  ShoppingListItem(
    id: '3',
    userId: 'u1',
    productName: 'Atta',
    ingredientId: 'atta',
    quantity: 5,
    unit: 'kg',
    source: ShoppingSource.ranOut,
    createdAt: fx.fixedToday,
  ),
  ShoppingListItem(
    id: '4',
    userId: 'u1',
    productName: 'Filter coffee',
    quantity: 1,
    unit: 'pack',
    source: ShoppingSource.manual,
    createdAt: fx.fixedToday,
  ),
  ShoppingListItem(
    id: '5',
    userId: 'u1',
    productName: 'Lemons',
    ingredientId: 'lemon',
    quantity: 6,
    source: ShoppingSource.manual,
    purchased: true,
    createdAt: fx.fixedToday,
  ),
];

/// Sheets are rendered over the page gradient the way they appear in the app,
/// so the golden shows the real contrast rather than a sheet on white.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0x730D2119),
        body: Align(alignment: Alignment.bottomCenter, child: child),
      );
}

void _noop() {}
