// Navigation, in one file.
//
// Every push in the app goes through here rather than being scattered across
// screens. Two reasons: the screens stay pure — they take callbacks and know
// nothing about routing, which is what makes all 52 renderable in a golden
// test — and the sequence of a flow is readable in one place instead of being
// reconstructed by following callbacks between files.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/engines/receipt_parser.dart';
import '../core/engines/recipe_scorer.dart';
import '../core/services/platform_capabilities.dart';
import '../core/widgets/item_row.dart';
import '../features/capture/widgets/live_viewfinders.dart';
import '../features/auth/screens/auth_page.dart';
import '../features/auth/screens/auth_screens.dart';
import '../features/capture/screens/barcode_screens.dart';
import '../features/capture/screens/receipt_screens.dart';
import '../features/dashboard/screens/home_states.dart';
import '../features/inventory/screens/item_screens.dart';
import '../features/notifications/screens/notification_screens.dart';
import '../features/profile/screens/profile_screens.dart';
import '../features/recipes/screens/recipe_screens.dart';
import '../features/shopping/screens/shopping_screens.dart';
import '../models/enums.dart';
import '../models/inventory_item.dart';
import '../models/models.dart';
import '../services/product_lookup.dart';
import '../services/sync_service.dart';
import 'app_scope.dart';
import 'shell.dart';

abstract final class Flows {
  static Future<T?> _push<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  // ------------------------------------------------------------- capture

  /// The centre Scan button. Goes to the chooser rather than straight to a
  /// camera, because which route is fastest depends on what the user is
  /// holding.
  static void openCapture(BuildContext context) =>
      _push<void>(context, const _ScanChooserRoute());

  static void openReceiptCamera(BuildContext context) =>
      _push<void>(context, const _ReceiptFlowRoute());

  static void openBarcodeScanner(BuildContext context) =>
      _push<void>(context, const _BarcodeFlowRoute());

  static void openAddByHand(BuildContext context, {String? barcode}) =>
      _push<void>(context, _AddByHandRoute(barcode: barcode));

  // ---------------------------------------------------------------- items

  static void openItem(BuildContext context, InventoryItem item) =>
      _push<void>(context, _ItemDetailRoute(itemId: item.id));

  static void openSearch(BuildContext context) =>
      _push<void>(context, const _SearchRoute());

  // -------------------------------------------------------------- recipes

  static void openRecipe(BuildContext context, RecipeMatch match) =>
      _push<void>(context, _RecipeDetailRoute(match: match));

  // ------------------------------------------------------------- shopping

  static void openShoppingList(BuildContext context) =>
      _push<void>(context, const ShoppingListRoute());

  static void openAddToList(BuildContext context) =>
      _push<void>(context, const _AddToListRoute());

  // -------------------------------------------------------------- profile

  static void openImpact(BuildContext context) =>
      _push<void>(context, const _ImpactRoute());

  static void openReminders(BuildContext context) =>
      _push<void>(context, const _RemindersRoute());

  static void openAccount(BuildContext context) =>
      _push<void>(context, const _AccountRoute());

  static void openAbout(BuildContext context) =>
      _push<void>(context, const _AboutRoute());

  static void openNotifications(BuildContext context) =>
      _push<void>(context, const NotificationsRoute());

  static void openSyncStatus(BuildContext context) =>
      _push<void>(context, const _SyncStatusRoute());

  static void openSignUp(BuildContext context) => _push<void>(
        context,
        const AuthPage(mode: CredentialsMode.signUp),
      );

  static Future<void> confirmSignOut(BuildContext context) async {
    final app = AppScope.read(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => SignOutSheet(
        pendingCount: app.sync.pendingCount,
        onSignOut: () => Navigator.of(sheet).pop(true),
        onCancel: () => Navigator.of(sheet).pop(false),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await app.signOut();
  }

  /// The permission ask, shown once, after the first item exists so the prompt
  /// can name something real.
  static Future<void> maybeAskForNotifications(
    BuildContext context,
    InventoryItem item,
  ) async {
    final app = AppScope.read(context);
    if (app.notificationsAsked) return;
    await app.markNotificationsAsked();
    if (!context.mounted) return;

    final days = item.expiryDate
        .difference(DateTime.now())
        .inDays
        .clamp(0, 999);

    final allow = await _push<bool>(
      context,
      NotificationPermissionScreen(
        firstItemName: item.productName.toLowerCase(),
        firstItemDays: days,
        glyphKey: ItemRow.glyphFor(item),
        onAllow: () => Navigator.of(context).pop(true),
        onNotNow: () => Navigator.of(context).pop(false),
      ),
    );
    if (allow == true) await app.reminders.requestPermission();
  }
}

// ==================================================================== 13

class _ScanChooserRoute extends StatelessWidget {
  const _ScanChooserRoute();

  @override
  Widget build(BuildContext context) => ScanChooserScreen(
        onBack: () => Navigator.of(context).pop(),
        onReceipt: () => Flows.openReceiptCamera(context),
        onBarcode: () => Flows.openBarcodeScanner(context),
        onByHand: () => Flows.openAddByHand(context),
      );
}

// ============================================================== 14–19

/// The receipt flow as one stateful route.
///
/// Camera, reading, review and summary are stages of a single task, not four
/// destinations. Modelling them as one route means the back button behaves —
/// backing out of Review returns to the camera, not to a half-parsed state
/// pushed onto a stack.
class _ReceiptFlowRoute extends StatefulWidget {
  const _ReceiptFlowRoute();

  @override
  State<_ReceiptFlowRoute> createState() => _ReceiptFlowRouteState();
}

enum _ReceiptStage { camera, reading, review, unreadable, summary }

class _ReceiptFlowRouteState extends State<_ReceiptFlowRoute> {
  _ReceiptStage _stage = _ReceiptStage.camera;
  ReadingStep _step = ReadingStep.reading;
  ParsedReceipt? _receipt;
  bool _torch = false;

  int _added = 0;
  String _soonestName = '';
  int _soonestDays = 0;

  /// Shutter: take a photo, then read it.
  Future<void> _capture() =>
      _readImage(() => AppScope.read(context).camera.capture());

  /// Everything after an image is obtained: OCR, parse, estimate, review.
  ///
  /// Both the shutter and the gallery route through here, taking the image
  /// source as a callback. Two copies of this pipeline is how the gallery path
  /// ends up quietly behind on a parser fix.
  Future<void> _readImage(Future<Uint8List?> Function() source) async {
    final app = AppScope.read(context);
    setState(() {
      _stage = _ReceiptStage.reading;
      _step = ReadingStep.reading;
    });

    final bytes = await source();
    if (!mounted) return;
    if (bytes == null) {
      // Backing out of the camera or the picker is not a failure.
      setState(() => _stage = _ReceiptStage.camera);
      return;
    }

    final text = await app.ocr.recognise(bytes);
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _stage = _ReceiptStage.unreadable);
      return;
    }

    setState(() => _step = ReadingStep.matching);
    final parser = ReceiptParser(aliases: app.reference.aliasMap());
    final parsed = parser.parse(text);
    if (!mounted) return;

    setState(() => _step = ReadingStep.estimating);
    // A beat so the third stage is legible rather than a flicker. Parsing is
    // fast; the honest thing is to show the step, not to fake a long wait.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (parsed.items.isEmpty) {
      setState(() => _stage = _ReceiptStage.unreadable);
      return;
    }
    setState(() {
      _receipt = parsed;
      _stage = _ReceiptStage.review;
    });
  }

  /// The gallery path. Shares everything after the image is obtained with the
  /// shutter path, so OCR, parsing and review cannot diverge between them.
  Future<void> _pickFromGallery() =>
      _readImage(() => AppScope.read(context).camera.pickFromGallery());

  Future<void> _toggleTorch() async {
    final camera = AppScope.read(context).camera;
    setState(() => _torch = !_torch);
    if (camera is DeviceCameraService) await camera.setTorch(_torch);
  }

  Future<void> _confirm() async {
    final app = AppScope.read(context);
    final receipt = _receipt;
    if (receipt == null) return;

    final ready = receipt.items.where((i) => !i.needsInput).toList();
    final added = <InventoryItem>[];
    for (final line in ready) {
      final ingredient = app.reference.ingredientByName(line.canonicalName!);
      await app.addItem(
        name: line.rawName,
        category: ingredient?.category ?? FoodCategory.other,
        quantity: line.quantity.toDouble(),
        unit: line.unit ?? ingredient?.defaultUnit ?? 'pcs',
        storage: ingredient?.suggestedStorage ?? StorageLocation.pantry,
        ingredientId: ingredient?.id,
      );
      final saved = app.allItems.firstWhere((i) => i.productName == line.rawName,
          orElse: () => app.allItems.last);
      added.add(saved);
    }
    if (!mounted) return;

    added.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    final soonest = added.isEmpty ? null : added.first;

    setState(() {
      _added = ready.length;
      _soonestName = soonest?.productName.toLowerCase() ?? '';
      _soonestDays = soonest == null
          ? 0
          : soonest.expiryDate
              .difference(DateTime.now())
              .inDays
              .clamp(0, 999);
      _stage = _ReceiptStage.summary;
    });

    if (soonest != null) {
      await Flows.maybeAskForNotifications(context, soonest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Promoted to a local so `is` narrows the type. The fake camera used on
    // web and in tests is not a DeviceCameraService, and gets no preview — the
    // screen falls back to its dark backdrop, which is what the goldens show.
    final camera = app.camera;
    return switch (_stage) {
      _ReceiptStage.camera => ReceiptCameraScreen(
          viewfinder: camera is DeviceCameraService
              ? CameraViewfinder(service: camera)
              : null,
          torchOn: _torch,
          onToggleTorch: _toggleTorch,
          onBack: () => Navigator.of(context).pop(),
          onShutter: _capture,
          onGallery: _pickFromGallery,
        ),
      _ReceiptStage.reading => ReadingReceiptScreen(
          step: _step,
          onCancel: () => setState(() => _stage = _ReceiptStage.camera),
        ),
      _ReceiptStage.unreadable => ReceiptUnreadableScreen(
          onBack: () => Navigator.of(context).pop(),
          onRetake: () => setState(() => _stage = _ReceiptStage.camera),
          onByHand: () {
            Navigator.of(context).pop();
            Flows.openAddByHand(context);
          },
        ),
      _ReceiptStage.review => ReviewReceiptScreen(
          receipt: _receipt!,
          categoryOf: (line) =>
              app.reference.ingredientByName(line.canonicalName ?? '')
                  ?.category ??
              FoodCategory.other,
          glyphOf: (line) =>
              app.reference.ingredientByName(line.canonicalName ?? '')
                  ?.glyphKey ??
              'cat-pantry',
          suppressed: _suppressed(app),
          onBack: () => setState(() => _stage = _ReceiptStage.camera),
          onConfirm: _confirm,
          onRemoveRow: (line) => setState(() {
            _receipt = ParsedReceipt(
              items: _receipt!.items.where((i) => i != line).toList(),
              skippedLines: _receipt!.skippedLines,
            );
          }),
          onEditRow: (line) => Flows.openAddByHand(context),
        ),
      _ReceiptStage.summary => AddedSummaryScreen(
          addedCount: _added,
          soonestName: _soonestName,
          soonestDays: _soonestDays,
          pendingCount: _receipt?.needsInputCount ?? 0,
          onSeeKitchen: () => Navigator.of(context).pop(),
          onDone: () => setState(() => _stage = _ReceiptStage.camera),
        ),
    };
  }

  /// Names on the receipt the user already has in. Screen 16's promise.
  List<String> _suppressed(AppState app) {
    final receipt = _receipt;
    if (receipt == null) return const [];
    final out = <String>[];
    for (final line in receipt.items) {
      final name = line.canonicalName;
      if (name == null) continue;
      final ing = app.reference.ingredientByName(name);
      if (ing != null && app.inventory.alreadyHave(ing.id)) out.add(name);
    }
    return out;
  }
}

// ============================================================== 20–22

class _BarcodeFlowRoute extends StatefulWidget {
  const _BarcodeFlowRoute();

  @override
  State<_BarcodeFlowRoute> createState() => _BarcodeFlowRouteState();
}

class _BarcodeFlowRouteState extends State<_BarcodeFlowRoute> {
  Product? _found;
  String? _unknownCode;

  /// The barcode currently being looked up, or null. Drives the interstitial.
  String? _looking;

  /// Why a lookup missed, so screen 22 can distinguish "we do not know this
  /// product" from "we could not reach the internet to ask".
  ProductSource? _missReason;

  /// Whether the answer came from the local cache rather than the network.
  bool _fromCache = true;
  bool _torch = false;
  int _quantity = 1;
  StorageLocation _storage = StorageLocation.fridge;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  Future<void> _listen() async {
    final app = AppScope.read(context);
    await for (final result in app.barcode.scan()) {
      if (!mounted) return;
      await app.barcode.stop();

      // Cache first, then Open Food Facts. The lookup can touch the network,
      // so the screen says it is working rather than appearing to freeze on
      // the frame that just scanned.
      setState(() => _looking = result.value);
      final outcome = await app.resolveBarcode(result.value);
      if (!mounted) return;

      setState(() {
        _looking = null;
        final product = outcome.product;
        if (product == null) {
          _unknownCode = result.value;
          _missReason = outcome.source;
        } else {
          _found = product;
          _fromCache = outcome.source == ProductSource.cache;
          _storage = app.reference
                  .ingredientById(product.ingredientId ?? '')
                  ?.suggestedStorage ??
              StorageLocation.fridge;
        }
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    if (_looking != null) {
      return ReadingReceiptScreen(
        step: ReadingStep.matching,
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    if (_unknownCode != null) {
      return BarcodeUnknownScreen(
        barcode: _unknownCode!,
        offline: _missReason == ProductSource.offline,
        onBack: () => Navigator.of(context).pop(),
        onScanAnother: () {
          setState(() => _unknownCode = null);
          _listen();
        },
        onAddByHand: () {
          Navigator.of(context).pop();
          Flows.openAddByHand(context, barcode: _unknownCode);
        },
      );
    }

    final product = _found;
    if (product == null) {
      final scanner = app.barcode;
      return BarcodeScannerScreen(
        viewfinder: scanner is MobileScannerBarcodeService
            ? BarcodeViewfinder(service: scanner)
            : null,
        torchOn: _torch,
        onToggleTorch: () async {
          setState(() => _torch = !_torch);
          if (scanner is MobileScannerBarcodeService) {
            await scanner.toggleTorch();
          }
        },
        onBack: () => Navigator.of(context).pop(),
        onByHand: () {
          Navigator.of(context).pop();
          Flows.openAddByHand(context);
        },
      );
    }

    final ingredient =
        app.reference.ingredientById(product.ingredientId ?? '');
    final estimate = AppState.estimator.estimate(
      ingredient: ingredient,
      category: ingredient?.category ?? FoodCategory.other,
      storage: _storage,
      purchaseDate: DateTime.now(),
    );

    return BarcodeFoundScreen(
      productName: product.productName,
      brand: product.brand,
      category: ingredient?.category ?? FoodCategory.other,
      glyphKey: ingredient?.glyphKey ?? 'cat-pantry',
      barcode: product.barcode,
      expiryLine: 'Best used by ${_dayMonth(estimate.date)}',
      expiryReason: estimate.reason,
      quantity: _quantity,
      storage: _storage,
      onQuantityChanged: (v) => setState(() => _quantity = v),
      onStorageChanged: (s) => setState(() => _storage = s),
      fromCache: _fromCache,
      onBack: () => Navigator.of(context).pop(),
      onEditExpiry: () {
        Navigator.of(context).pop();
        Flows.openAddByHand(context, barcode: product.barcode);
      },
      onConfirm: () async {
        await app.addItem(
          name: product.productName,
          category: ingredient?.category ?? FoodCategory.other,
          quantity: _quantity.toDouble(),
          unit: ingredient?.defaultUnit ?? 'pcs',
          storage: _storage,
          ingredientId: ingredient?.id,
          barcode: product.barcode,
        );
        if (!context.mounted) return;
        final added = app.allItems.last;
        await Flows.maybeAskForNotifications(context, added);
        if (context.mounted) Navigator.of(context).pop();
      },
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}

// ==================================================================== 23

class _AddByHandRoute extends StatefulWidget {
  const _AddByHandRoute({this.barcode});

  final String? barcode;

  @override
  State<_AddByHandRoute> createState() => _AddByHandRouteState();
}

String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _AddByHandRouteState extends State<_AddByHandRoute> {
  /// What the user has typed so far, so the catalogue suggestions track it.
  /// Held here rather than inside the screen because the lookup needs the
  /// repository, and the screen deliberately knows nothing about one.
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AddByHandScreen(
      prefilledBarcode: widget.barcode,
      // Title-cased: the catalogue stores canonical names in lower case, and
      // a chip reading "spinach" next to a field the user typed into looks
      // like data that leaked rather than a suggestion.
      suggestions: app.reference
          .suggest(_typed, limit: 4)
          .map((i) => _title(i.canonicalName))
          .toList(),
      onBack: () => Navigator.of(context).pop(),
      onNameChanged: (text) => setState(() => _typed = text),
      onSave: (name, quantity, unit, storage, category) async {
        await app.addItem(
          name: name,
          category: category,
          quantity: quantity.toDouble(),
          unit: unit,
          storage: storage,
          barcode: widget.barcode,
        );
        // Screen 22 promised we would remember it. Cache the barcode so the
        // next scan resolves instantly, and share it so others benefit.
        if (widget.barcode != null) {
          await app.rememberBarcode(
            barcode: widget.barcode!,
            productName: name,
            category: category,
          );
        }
        if (!context.mounted) return;
        await Flows.maybeAskForNotifications(context, app.allItems.last);
        if (context.mounted) Navigator.of(context).pop();
      },
    );
  }
}

// ==================================================================== 12

class _SearchRoute extends StatefulWidget {
  const _SearchRoute();

  @override
  State<_SearchRoute> createState() => _SearchRouteState();
}

class _SearchRouteState extends State<_SearchRoute> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SearchScreen(
      query: _query,
      results: _query.isEmpty ? const [] : app.inventory.search(_query),
      onQueryChanged: (q) => setState(() => _query = q),
      onBack: () => Navigator.of(context).pop(),
      onItemTap: (item) => Flows.openItem(context, item),
      onAddByHand: () => Flows.openAddByHand(context),
    );
  }
}

// ============================================================== 29–31

class _ItemDetailRoute extends StatelessWidget {
  const _ItemDetailRoute({required this.itemId});

  /// Held by id, not by value: the item is edited from this screen, and a
  /// captured copy would go stale the moment it was.
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final item = app.inventory.byId(itemId);
    // The item can vanish under this screen — "I used it" removes it while the
    // screen is still on the stack during the pop animation.
    if (item == null) return const SizedBox.shrink();

    return ItemDetailScreen(
      item: item,
      expiryLine: app.expiryLine(item),
      recipeSuggestions: [
        for (final match in app.rankedRecipes().take(6))
          if (match.haveNames.contains(item.ingredientId) ||
              match.haveNames.any((n) =>
                  n.toLowerCase() == item.productName.toLowerCase()))
            (
              name: match.name,
              matchLabel: match.matchLabel,
              imageKey: match.imageKey
            ),
      ],
      onBack: () => Navigator.of(context).pop(),
      onEdit: () => _edit(context, app, item),
      onQuantityChanged: (v) =>
          app.updateItem(item.copyWith(quantity: v.toDouble())),
      onUsedIt: () async {
        await app.markUsed(item);
        if (context.mounted) Navigator.of(context).pop();
      },
      onRemove: () => _confirmRemove(context, app, item),
      onRecipeTap: (name) {
        final match = app
            .rankedRecipes()
            .where((m) => m.name == name)
            .firstOrNull;
        if (match != null) Flows.openRecipe(context, match);
      },
    );
  }

  Future<void> _edit(
      BuildContext context, AppState app, InventoryItem item) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (editContext) => EditItemScreen(
        item: item,
        expiryLabel: app.expiryLine(item),
        onBack: () => Navigator.of(editContext).pop(),
        onSave: (name, quantity, unit, storage, category) async {
          await app.updateItem(item.copyWith(
            productName: name,
            quantity: quantity,
            unit: unit,
            storage: storage,
            category: category,
          ));
          if (editContext.mounted) Navigator.of(editContext).pop();
        },
      ),
    ));
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState app, InventoryItem item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => RemoveItemSheet(
        item: item,
        onUsedIt: () => Navigator.of(sheet).pop('used'),
        onRemove: () => Navigator.of(sheet).pop('removed'),
        onCancel: () => Navigator.of(sheet).pop(),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'used') {
      await app.markUsed(item);
    } else {
      await app.removeItem(item);
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}

// ============================================================== 34–36, 38

class _RecipeDetailRoute extends StatefulWidget {
  const _RecipeDetailRoute({required this.match});

  final RecipeMatch match;

  @override
  State<_RecipeDetailRoute> createState() => _RecipeDetailRouteState();
}

class _RecipeDetailRouteState extends State<_RecipeDetailRoute> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final recipe = app.recipes.byId(widget.match.id);
    final match = widget.match;

    return RecipeDetailScreen(
      match: match,
      servings: recipe?.servings ?? 4,
      saved: app.recipes.savedIds().contains(match.id),
      onToggleSaved: () async {
        await app.recipes.toggleSaved(match.id);
        setState(() {});
      },
      ingredients: [
        for (final row in recipe?.ingredients ?? const [])
          IngredientLine(
            name: _title(row.canonicalName),
            amount: row.quantityLabel,
            have: match.haveNames.contains(row.canonicalName),
            optional: row.optional,
            urgent: match.urgentNames.contains(row.canonicalName),
          ),
      ],
      onBack: () => Navigator.of(context).pop(),
      onSeeMethod: () => _method(context, app, recipe),
      onCook: () => _cook(context, app, match),
      onAddMissingToList: () async {
        final skipped = await app.addMissingForRecipe(match);
        if (!context.mounted) return;
        final added = match.missingNames.length - skipped.length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added == 0
              ? 'You already have everything that was missing.'
              : '$added added to your shopping list.'),
        ));
      },
    );
  }

  Future<void> _method(
      BuildContext context, AppState app, Recipe? recipe) async {
    if (recipe == null) return;
    var step = 0;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (methodContext) => StatefulBuilder(
        builder: (_, setInner) => RecipeMethodScreen(
          name: recipe.name,
          steps: recipe.methodSteps,
          currentStep: step,
          onStepTap: (i) => setInner(() => step = i),
          onBack: () => Navigator.of(methodContext).pop(),
          onDone: () {
            Navigator.of(methodContext).pop();
            _cook(context, app, widget.match);
          },
        ),
      ),
    ));
  }

  Future<void> _cook(
      BuildContext context, AppState app, RecipeMatch match) async {
    final candidates = <CookedItem>[
      for (final item in app.allItems)
        if (match.haveNames.contains(item.ingredientId) ||
            match.haveNames
                .any((n) => n.toLowerCase() == item.productName.toLowerCase()))
          CookedItem(
            id: item.id,
            name: item.productName,
            amount: ItemRow.quantityLabel(item),
            glyphKey: ItemRow.glyphFor(item),
            urgent: match.urgentNames.contains(item.ingredientId),
          ),
    ];

    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (cookContext) => CookedItScreen(
        recipeName: match.name,
        used: candidates,
        onBack: () => Navigator.of(cookContext).pop(),
        onConfirm: (usedIds) async {
          for (final id in usedIds) {
            final item = app.inventory.byId(id);
            if (item != null) await app.markUsed(item, recipeId: match.id);
          }
          if (!cookContext.mounted) return;
          Navigator.of(cookContext).pop();
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    ));
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ==================================================================== 40

class _AddToListRoute extends StatelessWidget {
  const _AddToListRoute();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AddToListScreen(
      onBack: () => Navigator.of(context).pop(),
      alreadyHave: app.allItems.map((i) => i.productName).toList(),
      suggestions: app.reference
          .allIngredients()
          .take(6)
          .map((i) => _title(i.canonicalName))
          .toList(),
      onAdd: (name, quantity, unit) async {
        await app.addToShopping(name: name, quantity: quantity, unit: unit);
        if (context.mounted) Navigator.of(context).pop();
      },
    );
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ============================================================== 43–46, 50

class _ImpactRoute extends StatelessWidget {
  const _ImpactRoute();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = DateTime.now();
    return ImpactScreen(
      stats: app.kitchenStats(),
      monthLabel: '${_months[now.month - 1]} so far',
      recentRescues: app.stats.recentRescues(limit: 5),
      onBack: () => Navigator.of(context).pop(),
    );
  }
}

class _RemindersRoute extends StatelessWidget {
  const _RemindersRoute();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final settings = app.reminderSettings;
    return RemindersScreen(
      enabled: settings.enabled,
      threeDay: settings.threeDay,
      oneDay: settings.oneDay,
      sameDay: settings.sameDay,
      quietHours: '9 pm to 8 am',
      permissionGranted: app.notificationPermission,
      onRequestPermission: app.requestNotificationPermission,
      onChanged: app.setReminderSetting,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}

class _AccountRoute extends StatelessWidget {
  const _AccountRoute();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AccountScreen(
      email: app.email ?? '',
      memberSince: app.memberSinceLabel,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}

class _AboutRoute extends StatelessWidget {
  const _AboutRoute();

  @override
  Widget build(BuildContext context) => AboutScreen(
        version: AppState.version,
        onBack: () => Navigator.of(context).pop(),
        onLicences: () => showLicensePage(
          context: context,
          applicationName: 'ShelfLife',
          applicationVersion: AppState.version,
        ),
      );
}

class _SyncStatusRoute extends StatelessWidget {
  const _SyncStatusRoute();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sync = app.sync;
    return SyncStatusScreen(
      state: !sync.isOnline
          ? SyncState.offline
          : sync.phase == SyncPhase.running
              ? SyncState.syncing
              : sync.pendingCount > 0
                  ? SyncState.pending
                  : SyncState.synced,
      pendingCount: sync.pendingCount,
      exhaustedCount: sync.exhaustedCount,
      lastSyncedLabel: app.lastSyncedLabel,
      onBack: () => Navigator.of(context).pop(),
      onRetryNow: sync.drain,
    );
  }
}
