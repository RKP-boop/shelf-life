// The one place that owns the repositories and the session.
//
// Deliberately a ChangeNotifier behind an InheritedNotifier rather than a state
// management package. The app has one store, one set of repositories, and a
// handful of screens that read them — a package would add a dependency and a
// vocabulary without removing any of the work.
//
// Every read is synchronous and comes from Hive (Principle 6). Nothing here
// awaits the network on the read path; the network only drains the outbox.

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/engines/expiry_estimator.dart';
import '../core/engines/recipe_scorer.dart';
import '../core/services/capabilities.dart';
import '../database/local_store.dart';
import '../database/sync_queue.dart';
import '../models/enums.dart';
import '../models/ingredient.dart';
import '../models/inventory_item.dart';
import '../models/models.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/repositories.dart';
import '../repositories/stats_repository.dart';
import '../services/product_lookup.dart';
import '../services/reminder_service.dart';
import '../services/sync_service.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!.notifier!;
  }

  /// For callers that must not rebuild on every change — event handlers.
  static AppState read(BuildContext context) {
    final scope =
        context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget
            as AppScope;
    return scope.notifier!;
  }
}

class AppState extends ChangeNotifier {
  AppState({
    required this.store,
    required this.queue,
    required this.sync,
    required this.capabilities,
    required this.reminders,
    required this.productLookup,
  })  : inventory = InventoryRepository(store: store, queue: queue),
        reference = ReferenceRepository(store: store),
        shopping = ShoppingRepository(
          store: store,
          queue: queue,
          inventory: InventoryRepository(store: store, queue: queue),
        ),
        stats = StatsRepository(store: store) {
    recipes = RecipeRepository(store: store, inventory: inventory);
    sync.addListener(notifyListeners);
  }

  final LocalStore store;
  final SyncQueue queue;
  final SyncService sync;

  final Capabilities capabilities;
  final ReminderService reminders;
  final ProductLookupService productLookup;

  OcrService get ocr => capabilities.ocr;
  GoogleAuthService get googleAuth => capabilities.googleAuth;

  /// Whether to offer the Google button at all. False when the build carries
  /// no OAuth client id, so the option is absent rather than present-and-broken.
  bool get canSignInWithGoogle => capabilities.googleAuth.isAvailable;
  BarcodeScannerService get barcode => capabilities.barcode;
  CameraService get camera => capabilities.camera;

  final InventoryRepository inventory;
  final ReferenceRepository reference;
  final ShoppingRepository shopping;
  final StatsRepository stats;
  late final RecipeRepository recipes;

  static const estimator = ExpiryEstimator();

  /// Shown on the About screen. A constant of the build rather than a call to
  /// the package-info plugin: one fewer dependency for one string.
  static const version = "1.0.0";

  /// Whether the OS has granted notification permission. Cached because the
  /// settings screen reads it on every rebuild.
  bool _notificationPermission = false;
  bool get notificationPermission => _notificationPermission;

  Future<void> requestNotificationPermission() async {
    _notificationPermission = await reminders.requestPermission();
    // Turning permission on has to catch up the items added while it was off,
    // otherwise nothing already in the kitchen is ever reminded about.
    if (_notificationPermission) {
      for (final item in inventory.all()) {
        await _scheduleFor(item);
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- session

  String? get userId => store.currentUserId;
  bool get isGuest => store.isGuest;
  bool get isSignedIn => userId != null && !isGuest;

  /// Null when the user has not given a name — which is the normal case in
  /// guest mode, not an edge case.
  String? get displayName {
    final name = (store.meta.get('display_name') as String?)?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// The greeting. "Welcome, you" is what a fallback string produces, and it
  /// reads like a placeholder that escaped.
  String get greeting =>
      displayName == null ? 'Welcome' : 'Welcome, ${displayName!}';

  /// The home-screen title. With a fallback name this rendered as
  /// "you's kitchen".
  String get kitchenTitle =>
      displayName == null ? 'Your kitchen' : "${displayName!}'s kitchen";

  String? get email => store.meta.get('email') as String?;

  bool get onboardingSeen =>
      (store.meta.get('onboarding_seen') as bool?) ?? false;

  Future<void> markOnboardingSeen() async {
    await store.meta.put('onboarding_seen', true);
    notifyListeners();
  }

  bool get notificationsAsked =>
      (store.meta.get('notifications_asked') as bool?) ?? false;

  Future<void> markNotificationsAsked() async {
    await store.meta.put('notifications_asked', true);
    notifyListeners();
  }

  // --------------------------------------------------------------- reads
  //
  // Thin pass-throughs so screens never reach past AppState into a
  // repository — which is what keeps the wiring reviewable in one file.

  List<InventoryItem> get allItems => inventory.all();

  List<InventoryItem> needsUsing({DateTime? today}) =>
      inventory.needsUsing(today: today, limit: 8);

  List<RecipeMatch> rankedRecipes({DateTime? today}) =>
      recipes.ranked(today: today);

  KitchenStats kitchenStats({DateTime? today}) =>
      stats.compute(today: today);

  List<ShoppingListItem> get shoppingItems => shopping.all();

  int get shoppingCount => shopping.toBuy().length;

  /// Glyph for a shopping row, resolved through the catalogue. Falls back to
  /// the category marker, and finally the pantry marker for free text.
  String glyphForShopping(ShoppingListItem item) {
    final id = item.ingredientId;
    if (id == null) return 'cat-pantry';
    final ing = reference.ingredientById(id);
    return ing?.glyphKey ?? 'cat-pantry';
  }

  String expiryLine(InventoryItem item, {DateTime? today}) {
    final now = _dateOnly(today ?? DateTime.now());
    final expiry = _dateOnly(item.expiryDate);
    final days = expiry.difference(now).inDays;
    if (days < 0) {
      return 'Was best used ${_relative(-days)} ago';
    }
    return switch (days) {
      0 => 'Best used today',
      1 => 'Best used tomorrow',
      _ => 'Best used by ${_dayMonth(expiry)}',
    };
  }

  // -------------------------------------------------------------- writes

  /// [name] may be free text. When it resolves to a catalogue ingredient the
  /// estimator gets a per-item shelf life; when it does not, it falls back to
  /// the category default — and either way the reason says which.
  Future<void> addItem({
    required String name,
    required FoodCategory category,
    required double quantity,
    required String unit,
    required StorageLocation storage,
    String? ingredientId,
    String? barcode,
    DateTime? printedExpiry,
    DateTime? userExpiry,
  }) async {
    final ingredient = ingredientId != null
        ? reference.ingredientById(ingredientId)
        : _resolve(name);

    final item = await inventory.add(
      productName: name,
      category: ingredient?.category ?? category,
      quantity: quantity,
      unit: unit,
      storage: storage,
      purchaseDate: DateTime.now(),
      ingredient: ingredient,
      barcode: barcode,
      printedExpiry: printedExpiry,
      userExpiry: userExpiry,
    );
    await _scheduleFor(item);
    notifyListeners();
    sync.nudge();
  }

  Future<void> updateItem(InventoryItem item) async {
    await inventory.update(item);
    await _scheduleFor(item);
    notifyListeners();
    sync.nudge();
  }

  Future<void> markUsed(InventoryItem item, {String? recipeId}) async {
    await inventory.markUsed(item, recipeId: recipeId);
    await reminders.cancelFor(item.id);
    notifyListeners();
    sync.nudge();
  }

  Future<void> removeItem(InventoryItem item) async {
    await inventory.remove(item);
    await reminders.cancelFor(item.id);
    notifyListeners();
    sync.nudge();
  }

  Future<void> addToShopping({
    required String name,
    double? quantity,
    String? unit,
    ShoppingSource source = ShoppingSource.manual,
    String? recipeId,
    String? recipeName,
  }) async {
    await shopping.add(
      productName: name,
      quantity: quantity ?? 1,
      unit: unit,
      source: source,
      sourceRecipeId: recipeId,
      sourceRecipeName: recipeName,
    );
    notifyListeners();
    sync.nudge();
  }

  Future<void> togglePurchased(ShoppingListItem item) async {
    await shopping.setPurchased(item, !item.purchased);
    notifyListeners();
    sync.nudge();
  }

  Future<void> removeFromShopping(ShoppingListItem item) async {
    await shopping.remove(item);
    notifyListeners();
    sync.nudge();
  }

  /// Adds a recipe's missing ingredients to the list.
  ///
  /// Returns the names it *skipped* because they are already in the kitchen —
  /// which is what screen 38 reports back ("you already have onions").
  Future<List<String>> addMissingForRecipe(RecipeMatch match) async {
    final skipped = await shopping.addMissingFor(
      match,
      nameToIngredientId: _nameToIngredientId(),
    );
    notifyListeners();
    sync.nudge();
    return skipped;
  }

  /// Canonical name -> ingredient id, for the recipe-to-shopping hop. Built on
  /// demand: the catalogue is 65 rows, so caching it would be premature.
  Map<String, String> _nameToIngredientId() => {
        for (final ing in reference.allIngredients())
          ing.canonicalName: ing.id,
      };

  /// Resolves free text through the alias table, so "palak" finds spinach.
  Ingredient? _resolve(String text) {
    final direct = reference.ingredientByName(text);
    if (direct != null) return direct;
    final canonical = reference.aliasMap()[text.trim().toLowerCase()];
    return canonical == null ? null : reference.ingredientByName(canonical);
  }

  /// Schedules the three reminder stages for an item, subject to settings and
  /// the dedup ledger. Silently does nothing when notifications are off.
  Future<void> _scheduleFor(InventoryItem item) async {
    if (!reminderSettings.enabled) return;
    await reminders.scheduleFor(
      itemId: item.id,
      itemName: item.productName,
      expiry: item.expiryDate,
      levels: reminderSettings.activeLevels,
    );
  }

  // ------------------------------------------------------------- auth
  //
  // Each method returns null on success, or a sentence to show the user. That
  // shape is deliberate: it keeps Supabase exception vocabulary out of the
  // widgets, and forces every failure to be phrased as something a person can
  // act on rather than surfaced as a code.

  SupabaseClient? get _auth => sync.client;

  /// Signs in with Google and adopts any rows added in guest mode.
  ///
  /// The only account path in the app. Email sign-up was removed because the
  /// Supabase project cannot send a confirmation code -- template editing is
  /// gated behind custom SMTP, the default template carries a link and no
  /// token, and the send limit is two emails an hour project-wide.
  ///
  /// Returns null on success, null again if the user simply backed out of the
  /// account picker, and a sentence otherwise. Cancelling deliberately looks
  /// like success to the caller: the user changed their mind, and telling them
  /// so would be noise.
  Future<String?> signInWithGoogle() async {
    final api = _auth;
    if (api == null) return _noBackend;

    final result = await capabilities.googleAuth.signIn();
    if (!result.ok) {
      return switch (result.outcome!) {
        GoogleAuthOutcome.cancelled => null,
        // No fallback to suggest any more, so each of these says what to do
        // instead of naming a path that no longer exists.
        GoogleAuthOutcome.notConfigured =>
          "Google sign-in is not set up in this build. You can carry on "
              "without an account.",
        GoogleAuthOutcome.unavailable =>
          "Google sign-in is not available on this phone. You can carry on "
              "without an account.",
        GoogleAuthOutcome.refused =>
          "Google did not complete that sign-in. Have another go in a "
              "moment.",
      };
    }

    try {
      final credential = result.credential!;
      final res = await api.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: credential.idToken,
      );
      final id = res.user?.id;
      if (id == null) {
        return "That did not go through. Have another go in a moment.";
      }
      await _adopt(id, email: credential.email, name: credential.displayName);
      return null;
    } on AuthException catch (e) {
      return _humaniseAuth(e);
    } catch (_) {
      return _unreachable;
    }
  }


  /// Signs out and clears this device.
  ///
  /// Clearing is right rather than harsh: the rows are on the server, and
  /// leaving one account kitchen visible after signing out would be a real
  /// privacy failure on a shared phone.
  Future<void> signOut() async {
    await _auth?.auth.signOut();
    // Otherwise the next sign-in silently reuses the same Google account with
    // no picker, which looks like the sign-out did not work.
    await capabilities.googleAuth.signOut();
    await reminders.cancelAll();
    await store.clearUserData();
    notifyListeners();
  }

  /// Continues without an account. Nothing is queued for the server while
  /// guest mode is on, which is what SyncQueue already enforces.
  Future<void> continueAsGuest() async {
    await store.meta.put("is_guest", true);
    await store.meta.put("user_id", "guest");
    notifyListeners();
  }

  /// Attaches local rows to a real user id.
  ///
  /// This is the guest-upgrade path: everything added before signing up keeps
  /// its client-generated id and simply changes owner, so nothing is lost and
  /// no row is duplicated.
  Future<void> _adopt(String id, {required String email, String? name}) async {
    final wasGuest = store.isGuest;
    await store.meta.put("user_id", id);
    await store.meta.put("is_guest", false);
    await store.meta.put("email", email);
    if (name != null && name.isNotEmpty) {
      await store.meta.put("display_name", name);
    }
    if (store.meta.get("member_since") == null) {
      await store.meta.put("member_since", DateTime.now().toIso8601String());
    }
    if (wasGuest) await queue.rekey(id);
    notifyListeners();
    sync.nudge();
  }

  static const _noBackend =
      "This copy of the app is running without a server, so accounts are not "
      "available. Everything else works.";

  static const _unreachable =
      "We could not reach the server just now. Have another go in a moment.";

  /// Supabase auth messages are developer-facing. These are not.
  static String _humaniseAuth(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains("already registered") || m.contains("already been")) {
      return "There is already an account with that address. Try signing in "
          "instead.";
    }
    if (m.contains("invalid login")) {
      return "That email and password do not match. Try again, or reset your "
          "password.";
    }
    if (m.contains("password")) {
      return "That password is too short \u2014 eight characters or more.";
    }
    if (m.contains("email")) {
      return "That does not look like an email address.";
    }
    return "That did not go through. Have another go in a moment.";
  }

  // ------------------------------------------------------------- labels

  String get memberSinceLabel {
    final raw = store.meta.get("member_since") as String?;
    if (raw == null) return "today";
    final d = DateTime.tryParse(raw);
    return d == null ? "today" : "${_months[d.month - 1]} ${d.year}";
  }

  String get lastSyncedLabel {
    final raw = store.meta.get("last_synced") as String?;
    final d = raw == null ? sync.lastSynced : DateTime.tryParse(raw);
    if (d == null) return "not yet";
    final mins = DateTime.now().difference(d).inMinutes;
    if (mins < 1) return "just now";
    if (mins < 60) return "$mins ${mins == 1 ? "minute" : "minutes"} ago";
    final hours = mins ~/ 60;
    if (hours < 24) return "$hours ${hours == 1 ? "hour" : "hours"} ago";
    final days = hours ~/ 24;
    return "$days ${days == 1 ? "day" : "days"} ago";
  }


  // ------------------------------------------------------------- barcodes

  /// Resolves a barcode: local cache, then Open Food Facts, then give up.
  ///
  /// Cache first is not an optimisation, it is the offline-first rule — the
  /// seeded rows and anything this user has taught the app answer instantly
  /// with no connection. The network is only consulted on a miss.
  ///
  /// A network hit is written to the local cache and queued for the shared
  /// `products` table, so the next person to scan it gets a cache hit.
  Future<({Product? product, ProductSource source})> resolveBarcode(
      String barcode) async {
    final cached = reference.productByBarcode(barcode);
    if (cached != null) {
      return (product: cached, source: ProductSource.cache);
    }

    final hit = await productLookup.byBarcode(barcode);
    if (!hit.found) return (product: null, source: hit.source);

    // Resolve the looked-up name against the catalogue so the item still gets
    // a real shelf life rather than the category default.
    final ingredient = _resolve(hit.productName!) ??
        (hit.brand == null ? null : _resolve(hit.brand!));

    final product = Product(
      barcode: barcode,
      productName: hit.productName!,
      brand: hit.brand,
      ingredientId: ingredient?.id,
      category: hit.category ?? ingredient?.category,
      packSize: hit.packSize,
      // Not verified: it came from a public database, not from us. The column
      // exists precisely so a contributed row cannot masquerade as seeded.
      verified: false,
    );

    await _cacheProduct(product);
    return (product: product, source: ProductSource.network);
  }

  /// Writes a product to the local cache and queues it for the shared table.
  Future<void> _cacheProduct(Product product) async {
    await store.products.put(product.barcode, product.toJson());
    if (!isGuest) {
      await queue.enqueue(
        op: SyncOp.insert,
        table: SyncTable.products,
        rowId: product.barcode,
        payload: product.toJson(forWire: true),
      );
      sync.nudge();
    }
    notifyListeners();
  }

  /// Called when the user tells us what an unknown barcode is. The same cache
  /// path, so the next scan is instant either way.
  Future<void> rememberBarcode({
    required String barcode,
    required String productName,
    String? ingredientId,
    FoodCategory? category,
  }) =>
      _cacheProduct(Product(
        barcode: barcode,
        productName: productName,
        ingredientId: ingredientId,
        category: category,
        verified: false,
      ));

  // ------------------------------------------------------------ settings

  ReminderSettings get reminderSettings => ReminderSettings(
        enabled: (store.meta.get('notify_enabled') as bool?) ?? true,
        threeDay: (store.meta.get('notify_3d') as bool?) ?? true,
        oneDay: (store.meta.get('notify_1d') as bool?) ?? true,
        sameDay: (store.meta.get('notify_0d') as bool?) ?? true,
      );

  Future<void> setReminderSetting(String key, bool value) async {
    const keys = {
      'enabled': 'notify_enabled',
      'threeDay': 'notify_3d',
      'oneDay': 'notify_1d',
      'sameDay': 'notify_0d',
    };
    final metaKey = keys[key];
    if (metaKey == null) return;
    await store.meta.put(metaKey, value);
    notifyListeners();
    // Reschedule everything: turning a stage back on has to affect items that
    // were added while it was off.
    if (reminderSettings.enabled) {
      for (final item in inventory.all()) {
        await _scheduleFor(item);
      }
    } else {
      await reminders.cancelAll();
    }
  }

  // -------------------------------------------------------------- helpers

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String _relative(int days) =>
      days == 1 ? 'a day' : '$days days';

  @override
  void dispose() {
    sync.removeListener(notifyListeners);
    super.dispose();
  }
}

class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.threeDay,
    required this.oneDay,
    required this.sameDay,
  });

  final bool enabled;
  final bool threeDay;
  final bool oneDay;
  final bool sameDay;

  Set<NotificationLevel> get activeLevels => {
        if (threeDay) NotificationLevel.threeDay,
        if (oneDay) NotificationLevel.oneDay,
        if (sameDay) NotificationLevel.sameDay,
      };
}
