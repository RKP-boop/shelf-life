/// Reference, recipe and shopping repositories.
///
/// All read from Hive. Reference data (ingredients, aliases, recipes, products)
/// is seeded from Postgres once and cached indefinitely: it is identical for
/// every user, so re-fetching it on each launch would be waste and would make
/// a cold start depend on the network.
library;

import '../core/engines/recipe_scorer.dart';
import '../database/local_store.dart';
import '../database/sync_queue.dart';
import '../models/enums.dart';
import '../models/ingredient.dart';
import '../models/models.dart';
import 'inventory_repository.dart';

// ------------------------------------------------------------- reference

class ReferenceRepository {
  const ReferenceRepository({required this.store});

  final LocalStore store;

  List<Ingredient> allIngredients() =>
      store.readAll(store.ingredients).map(Ingredient.fromJson).toList();

  Ingredient? ingredientById(String id) {
    final raw = store.ingredients.get(id);
    return raw == null ? null : Ingredient.fromJson(LocalStore.cast(raw));
  }

  Ingredient? ingredientByName(String canonicalName) {
    final target = canonicalName.toLowerCase();
    for (final raw in store.ingredients.values) {
      final ing = Ingredient.fromJson(LocalStore.cast(raw));
      if (ing.canonicalName.toLowerCase() == target) return ing;
    }
    return null;
  }

  /// alias -> canonical name, in the shape the receipt parser expects.
  Map<String, String> aliasMap() {
    final map = <String, String>{};
    for (final raw in store.aliases.values) {
      final j = LocalStore.cast(raw);
      map[(j['alias'] as String).toLowerCase()] = j['canonical'] as String;
    }
    // canonical names resolve to themselves, so a receipt reading "spinach"
    // does not need a redundant alias row
    for (final ing in allIngredients()) {
      map.putIfAbsent(ing.canonicalName.toLowerCase(), () => ing.canonicalName);
    }
    return map;
  }

  /// Autocomplete for manual entry (screen 23). Prefix matches first, since a
  /// user typing "spin" expects "Spinach" before "Baby spinach".
  List<Ingredient> suggest(String term, {int limit = 8}) {
    final q = term.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final all = allIngredients();
    final prefix = all.where((i) => i.canonicalName.toLowerCase().startsWith(q));
    final contains = all.where((i) =>
        !i.canonicalName.toLowerCase().startsWith(q) &&
        i.canonicalName.toLowerCase().contains(q));
    return [...prefix, ...contains].take(limit).toList();
  }

  Product? productByBarcode(String barcode) {
    final raw = store.products.get(barcode);
    return raw == null ? null : Product.fromJson(LocalStore.cast(raw));
  }
}

// ---------------------------------------------------------------- recipes

class RecipeRepository {
  const RecipeRepository({
    required this.store,
    required this.inventory,
    this.scorer = const RecipeScorer(),
  });

  final LocalStore store;
  final InventoryRepository inventory;
  final RecipeScorer scorer;

  List<Recipe> all() =>
      store.readAll(store.recipes).map(Recipe.fromJson).toList();

  Recipe? byId(String id) {
    final raw = store.recipes.get(id);
    return raw == null ? null : Recipe.fromJson(LocalStore.cast(raw));
  }

  /// FR-07 ranking, computed locally so the Recipes tab works offline.
  List<RecipeMatch> ranked({DateTime? today, int limit = 20}) {
    final held = inventory.heldIngredients();
    final candidates = all()
        .map((r) => RecipeCandidate(
              id: r.id,
              name: r.name,
              prepMinutes: r.prepMinutes,
              imageKey: r.imageKey,
              ingredients: r.ingredients
                  .map((i) => RecipeIngredient(
                        ingredientId: i.ingredientId,
                        canonicalName: i.canonicalName,
                        optional: i.optional,
                      ))
                  .toList(),
            ))
        .toList();
    return scorer.rank(candidates, held, today: today, limit: limit);
  }

  /// Quick Meals filter — under 20 minutes, per the board.
  List<RecipeMatch> quickMeals({DateTime? today}) =>
      ranked(today: today, limit: 100)
          .where((m) => m.prepMinutes <= 20)
          .toList();

  /// Below this, the Recipes tab shows its empty state rather than a thin list
  /// of one-ingredient matches ("Add more ingredients to unlock recipe
  /// suggestions").
  static const int minimumItemsForSuggestions = 5;

  bool get hasEnoughToSuggest =>
      inventory.heldIngredients().length >= minimumItemsForSuggestions;

  Set<String> savedIds() =>
      ((store.meta.get('saved_recipes') as List?) ?? const [])
          .map((e) => e as String)
          .toSet();

  Future<void> toggleSaved(String recipeId) async {
    final saved = savedIds();
    saved.contains(recipeId) ? saved.remove(recipeId) : saved.add(recipeId);
    await store.meta.put('saved_recipes', saved.toList());
  }

  List<Recipe> saved() {
    final ids = savedIds();
    return all().where((r) => ids.contains(r.id)).toList();
  }
}

// --------------------------------------------------------------- shopping

class ShoppingRepository {
  const ShoppingRepository({
    required this.store,
    required this.queue,
    required this.inventory,
  });

  final LocalStore store;
  final SyncQueue queue;
  final InventoryRepository inventory;

  List<ShoppingListItem> all() {
    final items = store
        .readAll(store.shopping)
        .map(ShoppingListItem.fromJson)
        .toList();
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  List<ShoppingListItem> toBuy() => all().where((i) => !i.purchased).toList();
  List<ShoppingListItem> inBasket() => all().where((i) => i.purchased).toList();

  Future<ShoppingListItem> add({
    required String productName,
    ShoppingSource source = ShoppingSource.manual,
    String? ingredientId,
    double quantity = 1,
    String? unit,
    String? sourceRecipeId,
    String? sourceRecipeName,
  }) async {
    final item = ShoppingListItem(
      id: InventoryRepository.newId(),
      userId: store.currentUserId ?? 'guest',
      ingredientId: ingredientId,
      productName: productName,
      quantity: quantity,
      unit: unit,
      source: source,
      sourceRecipeId: sourceRecipeId,
      sourceRecipeName: sourceRecipeName,
      createdAt: DateTime.now(),
    );
    await store.shopping.put(item.id, item.toJson());
    await queue.enqueue(
      op: SyncOp.insert,
      table: SyncTable.shopping,
      rowId: item.id,
      payload: item.toJson(forWire: true),
    );
    return item;
  }

  /// Add a recipe's missing ingredients, skipping anything already held.
  ///
  /// The suppression is what screen 39's blue strip reports: "You already have
  /// onions and rice, we've left them off." Returns the names that were
  /// skipped so the UI can say so rather than silently doing less.
  Future<List<String>> addMissingFor(
    RecipeMatch match, {
    required Map<String, String> nameToIngredientId,
  }) async {
    final skipped = <String>[];
    for (final name in match.missingNames) {
      final ingredientId = nameToIngredientId[name];
      if (ingredientId != null && inventory.alreadyHave(ingredientId)) {
        skipped.add(name);
        continue;
      }
      await add(
        productName: name,
        source: ShoppingSource.recipe,
        ingredientId: ingredientId,
        sourceRecipeId: match.id,
        sourceRecipeName: match.name,
      );
    }
    return skipped;
  }

  Future<void> setPurchased(ShoppingListItem item, bool purchased) async {
    final updated = item.copyWith(purchased: purchased);
    await store.shopping.put(updated.id, updated.toJson());
    await queue.enqueue(
      op: SyncOp.update,
      table: SyncTable.shopping,
      rowId: updated.id,
      payload: updated.toJson(forWire: true),
    );
  }

  Future<void> remove(ShoppingListItem item) async {
    await store.shopping.delete(item.id);
    await queue.enqueue(
      op: SyncOp.delete,
      table: SyncTable.shopping,
      rowId: item.id,
      payload: {'id': item.id},
    );
  }

  /// BR-06 made explicit: this is the ONLY path from the shopping list into
  /// inventory, and it exists solely because the user tapped the confirm
  /// button. Nothing else in the app moves an item across.
  Future<int> confirmPurchasedIntoKitchen({
    required Ingredient? Function(String? ingredientId) lookup,
    DateTime? today,
  }) async {
    final basket = inBasket();
    for (final item in basket) {
      final ingredient = lookup(item.ingredientId);
      await inventory.add(
        productName: item.productName,
        category: ingredient?.category ?? FoodCategory.other,
        quantity: item.quantity,
        unit: item.unit ?? ingredient?.defaultUnit ?? 'pcs',
        storage: StorageLocation.fridge,
        purchaseDate: today ?? DateTime.now(),
        ingredient: ingredient,
        today: today,
      );
      await remove(item);
    }
    return basket.length;
  }
}
