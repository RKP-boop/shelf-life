// Barcode lookup against Open Food Facts.
//
// This supersedes D1, which said the seeded cache was the only lookup path.
// That decision was made because no API had been chosen; the consequence in
// practice was that scanning anything outside the 40 seeded barcodes asked the
// user to type the product in, every time. Open Food Facts fixes that: free,
// no API key, open data (ODbL), and good coverage of packaged food including
// Indian brands.
//
// The order is cache, then network, then ask — never the other way round:
//
//   1. The local Hive `products` box. Instant, works offline, and holds both
//      the seeded rows and anything this user has taught the app.
//   2. Open Food Facts, but only when online, and with a short timeout. A
//      scanner that hangs for thirty seconds on a bad connection is worse than
//      one that asks.
//   3. The "tell us what it is" screen, unchanged. Still the honest fallback,
//      just reached far less often.
//
// A hit from the network is written to the local cache and queued for the
// shared `products` table, which is what makes screen 22's promise — "we will
// remember it for next time" — true for everyone rather than just this phone.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/enums.dart';

/// What a lookup produced, and where it came from.
///
/// The source matters to the UI: a cached hit is certain enough to show
/// straight away, a network hit is worth marking as "found online" so the user
/// knows to sanity-check the name.
enum ProductSource { cache, network, notFound, offline }

class ProductLookupResult {
  const ProductLookupResult({
    required this.source,
    this.productName,
    this.brand,
    this.packSize,
    this.category,
  });

  const ProductLookupResult.miss(this.source)
      : productName = null,
        brand = null,
        packSize = null,
        category = null;

  final ProductSource source;
  final String? productName;
  final String? brand;
  final String? packSize;
  final FoodCategory? category;

  bool get found => productName != null && productName!.trim().isNotEmpty;
}

abstract interface class ProductLookupService {
  Future<ProductLookupResult> byBarcode(String barcode);
}

class OpenFoodFactsLookup implements ProductLookupService {
  OpenFoodFactsLookup({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Short by design. This runs while the user is holding a packet up to the
  /// camera, so a slow answer is nearly as bad as no answer.
  final Duration timeout;

  /// Open Food Facts asks that clients identify themselves so they can contact
  /// you about abusive traffic instead of blocking the whole user agent. Being
  /// a good citizen of a free service someone else pays for.
  static const _userAgent =
      'ShelfLife/1.0 (kitchen inventory app; github.com/RKP-boop/shelf-life)';

  /// Only the fields actually used, so the response stays small on a phone
  /// connection — the full product record is enormous.
  static const _fields =
      'product_name,product_name_en,brands,quantity,categories_tags';

  @override
  Future<ProductLookupResult> byBarcode(String barcode) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$barcode.json',
      {'fields': _fields},
    );

    try {
      final res = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(timeout);

      // 404 is the normal "we do not have this barcode" answer, not a fault.
      if (res.statusCode == 404) {
        return const ProductLookupResult.miss(ProductSource.notFound);
      }
      if (res.statusCode != 200) {
        return const ProductLookupResult.miss(ProductSource.notFound);
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 1) {
        return const ProductLookupResult.miss(ProductSource.notFound);
      }

      final product = (body['product'] as Map?)?.cast<String, dynamic>();
      if (product == null) {
        return const ProductLookupResult.miss(ProductSource.notFound);
      }

      final name = _firstNonEmpty([
        product['product_name_en'] as String?,
        product['product_name'] as String?,
      ]);
      if (name == null) {
        // A record with no usable name is a miss, not a hit with a blank
        // label — the review screen would show an empty row.
        return const ProductLookupResult.miss(ProductSource.notFound);
      }

      return ProductLookupResult(
        source: ProductSource.network,
        productName: name,
        brand: _firstBrand(product['brands'] as String?),
        packSize: _trimmed(product['quantity'] as String?),
        category: _categoryFrom(product['categories_tags']),
      );
    } on TimeoutException {
      return const ProductLookupResult.miss(ProductSource.offline);
    } catch (_) {
      // No connection, DNS failure, malformed JSON. All the same to the user:
      // we could not look it up, so ask instead.
      return const ProductLookupResult.miss(ProductSource.offline);
    }
  }

  static String? _trimmed(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static String? _firstNonEmpty(List<String?> options) {
    for (final o in options) {
      final t = _trimmed(o);
      if (t != null) return t;
    }
    return null;
  }

  /// `brands` is a comma-separated list, most-specific first.
  static String? _firstBrand(String? brands) =>
      _trimmed(brands?.split(',').first);

  /// Maps Open Food Facts category tags onto the six the app knows.
  ///
  /// Their taxonomy has thousands of entries, so this checks for the words that
  /// actually discriminate and gives up rather than guessing. A wrong category
  /// produces a wrong shelf-life estimate, which is worse than the user
  /// picking one.
  static FoodCategory? _categoryFrom(Object? tags) {
    if (tags is! List) return null;
    final joined = tags.whereType<String>().join(' ').toLowerCase();

    // Order matters: frozen beats whatever the food actually is, because how
    // it is stored dominates how long it keeps.
    if (joined.contains('frozen')) return FoodCategory.frozen;
    if (joined.contains('dairy') ||
        joined.contains('milk') ||
        joined.contains('cheese') ||
        joined.contains('yogurt') ||
        joined.contains('butter')) {
      return FoodCategory.dairy;
    }
    if (joined.contains('fresh-vegetable') ||
        joined.contains('vegetables')) {
      return FoodCategory.vegetables;
    }
    if (joined.contains('fresh-fruit') || joined.contains('fruits')) {
      return FoodCategory.fruits;
    }
    if (joined.contains('cereal') ||
        joined.contains('flour') ||
        joined.contains('rice') ||
        joined.contains('pulse') ||
        joined.contains('legume') ||
        joined.contains('spice') ||
        joined.contains('condiment') ||
        joined.contains('snack') ||
        joined.contains('beverage')) {
      return FoodCategory.pantry;
    }
    return null;
  }
}

/// Returns a canned answer. Defaults to a miss so tests exercise the
/// ask-the-user path unless they opt into a hit.
class FakeProductLookup implements ProductLookupService {
  FakeProductLookup({this.result});

  ProductLookupResult? result;

  /// Barcodes asked about, in order. Lets a test assert the cache was
  /// consulted first and the network never touched.
  final List<String> asked = [];

  @override
  Future<ProductLookupResult> byBarcode(String barcode) async {
    asked.add(barcode);
    return result ?? const ProductLookupResult.miss(ProductSource.notFound);
  }
}
