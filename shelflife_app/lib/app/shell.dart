// The navigation shell.
//
// Four tabs with an IndexedStack, so switching tabs keeps each tab's scroll
// position and does not rebuild the world. The centre Scan button is not a tab
// — it pushes the capture flow, which is why NavTab.scan is intercepted here
// rather than becoming a fifth index.

import 'package:flutter/material.dart';

import '../core/widgets/bottom_nav.dart';
import '../core/widgets/item_row.dart';
import '../features/dashboard/screens/home_screen.dart';
import '../features/dashboard/screens/home_states.dart';
import '../features/inventory/screens/inventory_screen.dart';
import '../features/notifications/screens/notification_screens.dart';
import '../features/profile/screens/profile_screens.dart';
import '../features/recipes/screens/recipe_screens.dart';
import '../features/shopping/screens/shopping_screens.dart';
import '../models/enums.dart';
import '../models/inventory_item.dart';
import '../services/sync_service.dart';
import 'app_scope.dart';
import 'flows.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  NavTab _tab = NavTab.home;

  /// Per-tab state that has to survive a tab switch.
  InventoryGrouping _grouping = InventoryGrouping.none;
  InventorySort _sort = InventorySort.soonestFirst;
  StorageLocation? _storageFilter;
  FoodCategory? _categoryFilter;
  RecipeFilter _recipeFilter = RecipeFilter.useSoonest;

  void _onTab(NavTab tab) {
    if (tab == NavTab.scan) {
      Flows.openCapture(context);
      return;
    }
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final index = switch (_tab) {
      NavTab.home => 0,
      NavTab.inventory => 1,
      NavTab.recipes => 2,
      NavTab.profile => 3,
      NavTab.scan => 0,
    };

    return IndexedStack(
      index: index,
      children: [
        _home(app),
        _inventory(app),
        _recipes(app),
        _profile(app),
      ],
    );
  }

  // ------------------------------------------------------------------ home

  Widget _home(AppState app) {
    final items = app.allItems;
    if (items.isEmpty) {
      return HomeEmptyScreen(
        greeting: app.greeting,
        onTabChanged: _onTab,
        onScanReceipt: () => Flows.openReceiptCamera(context),
        onScanBarcode: () => Flows.openBarcodeScanner(context),
        onAddByHand: () => Flows.openAddByHand(context),
      );
    }
    return HomeScreen(
      kitchenTitle: app.kitchenTitle,
      needsUsing: app.needsUsing(),
      suggestions: app.rankedRecipes().take(3).toList(),
      stats: app.kitchenStats(),
      shoppingCount: app.shoppingCount,
      onTabChanged: _onTab,
      onItemTap: (item) => Flows.openItem(context, item),
      onRecipeTap: (match) => Flows.openRecipe(context, match),
      onSearchTap: () => Flows.openSearch(context),
      onNotificationsTap: () => Flows.openNotifications(context),
      onShoppingTap: () => Flows.openShoppingList(context),
    );
  }

  // ------------------------------------------------------------- inventory

  Widget _inventory(AppState app) => InventoryScreen(
        items: app.allItems,
        grouping: _grouping,
        sort: _sort,
        storageFilter: _storageFilter,
        categoryFilter: _categoryFilter,
        onTabChanged: _onTab,
        onItemTap: (item) => Flows.openItem(context, item),
        onSearchTap: () => Flows.openSearch(context),
        onFilterTap: _openFilterSheet,
        onGroupingChanged: (g) => setState(() {
          _grouping = g;
          // Tapping a grouping pill also clears a filter, because the empty
          // state's "Show everything" action routes through here.
          _storageFilter = null;
          _categoryFilter = null;
        }),
        onAdd: () => Flows.openCapture(context),
      );

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheet) => InventoryFilterSheet(
          sort: _sort,
          storageFilter: _storageFilter,
          categoryFilter: _categoryFilter,
          onSortChanged: (s) => setSheet(() => setState(() => _sort = s)),
          onStorageChanged: (s) =>
              setSheet(() => setState(() => _storageFilter = s)),
          onCategoryChanged: (c) =>
              setSheet(() => setState(() => _categoryFilter = c)),
          onClear: () => setSheet(() => setState(() {
                _sort = InventorySort.soonestFirst;
                _storageFilter = null;
                _categoryFilter = null;
              })),
          onApply: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- recipes

  Widget _recipes(AppState app) => RecipesScreen(
        matches: app.rankedRecipes(),
        filter: _recipeFilter,
        onFilterChanged: (f) => setState(() => _recipeFilter = f),
        onTabChanged: _onTab,
        onRecipeTap: (match) => Flows.openRecipe(context, match),
        onAddItems: () => Flows.openCapture(context),
      );

  // --------------------------------------------------------------- profile

  Widget _profile(AppState app) => ProfileScreen(
        displayName: app.displayName ?? 'You',
        email: app.email,
        stats: app.kitchenStats(),
        isGuest: app.isGuest,
        syncState: _syncState(app),
        pendingCount: app.sync.pendingCount,
        onTabChanged: _onTab,
        onImpact: () => Flows.openImpact(context),
        onReminders: () => Flows.openReminders(context),
        onAccount: () => Flows.openAccount(context),
        onAbout: () => Flows.openAbout(context),
        onSignOut: () => Flows.confirmSignOut(context),
        onSignIn: () => Flows.signInWithGoogle(context),
      );

  static SyncState _syncState(AppState app) {
    if (!app.sync.isOnline) return SyncState.offline;
    return switch (app.sync.phase) {
      SyncPhase.running => SyncState.syncing,
      SyncPhase.offline => SyncState.offline,
      SyncPhase.idle =>
        app.sync.pendingCount > 0 ? SyncState.pending : SyncState.synced,
    };
  }
}

/// The shopping list and the reminders list are pushed rather than tabbed —
/// four tabs is the limit before the bar becomes a menu, and both of these are
/// reached from a specific place rather than browsed.
class ShoppingListRoute extends StatelessWidget {
  const ShoppingListRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ShoppingListScreen(
      items: app.shoppingItems,
      glyphOf: app.glyphForShopping,
      onBack: () => Navigator.of(context).pop(),
      onTogglePurchased: app.togglePurchased,
      onRemove: app.removeFromShopping,
      onClearPurchased: () async {
        for (final item in app.shopping.inBasket()) {
          await app.removeFromShopping(item);
        }
      },
      onAdd: () => Flows.openAddToList(context),
    );
  }
}

class NotificationsRoute extends StatelessWidget {
  const NotificationsRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = DateTime.now();
    return NotificationsScreen(
      onBack: () => Navigator.of(context).pop(),
      onSettings: () => Flows.openReminders(context),
      onSeeRecipes: () => Navigator.of(context).pop(),
      onEntryTap: (entry) {
        final item = app.inventory.byId(entry.id);
        if (item != null) Flows.openItem(context, item);
      },
      entries: [
        for (final item in app.allItems)
          if (_levelFor(item, now) case final level?)
            NotificationEntry(
              id: item.id,
              itemName: item.productName,
              level: level,
              detail: _detail(item, level),
              glyphKey: ItemRow.glyphFor(item),
              category: item.category,
            ),
      ],
    );
  }

  /// Which stage an item is currently in, or null when it is not due yet.
  static NotificationLevel? _levelFor(InventoryItem item, DateTime now) {
    final days = DateTime(item.expiryDate.year, item.expiryDate.month,
            item.expiryDate.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days <= 0) return NotificationLevel.sameDay;
    if (days == 1) return NotificationLevel.oneDay;
    if (days <= 3) return NotificationLevel.threeDay;
    return null;
  }

  static String _detail(InventoryItem item, NotificationLevel level) {
    final qty = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);
    return switch (level) {
      NotificationLevel.sameDay =>
        'Best used today — you have $qty ${item.unit}',
      NotificationLevel.oneDay => 'Tomorrow is its last good day',
      NotificationLevel.threeDay => 'A few days left',
    };
  }
}
