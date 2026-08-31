// Open Food Facts lookup.
//
// Tested against captured response shapes rather than the live service: a test
// that needs the internet fails on a train, and a test that hits someone
// else's free API on every run is rude.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/services/product_lookup.dart';

/// Returns a canned response, and records what was asked for.
class _StubClient extends http.BaseClient {
  _StubClient(this.status, this.body, {this.delay});

  final int status;
  final String body;
  final Duration? delay;

  Uri? lastUrl;
  Map<String, String> lastHeaders = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUrl = request.url;
    lastHeaders = request.headers;
    if (delay != null) await Future<void>.delayed(delay!);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
    );
  }
}

String _hit({
  String? name = 'Amul Taaza Toned Milk',
  String? nameEn,
  String brands = 'Amul, Amul Dairy',
  String quantity = '1 L',
  List<String> tags = const ['en:dairies', 'en:milks'],
}) =>
    jsonEncode({
      'status': 1,
      'product': {
        'product_name': ?name,
        'product_name_en': ?nameEn,
        'brands': brands,
        'quantity': quantity,
        'categories_tags': tags,
      },
    });

void main() {
  group('a hit', () {
    test('returns the product with brand and pack size', () async {
      final client = _StubClient(200, _hit());
      final result =
          await OpenFoodFactsLookup(client: client).byBarcode('8901030865278');

      expect(result.found, isTrue);
      expect(result.source, ProductSource.network);
      expect(result.productName, 'Amul Taaza Toned Milk');
      expect(result.brand, 'Amul', reason: 'first brand only');
      expect(result.packSize, '1 L');
      expect(result.category, FoodCategory.dairy);
    });

    test('prefers the English name when both are present', () async {
      final client = _StubClient(
          200, _hit(name: 'Lait demi-écrémé', nameEn: 'Semi-skimmed milk'));
      final result = await OpenFoodFactsLookup(client: client).byBarcode('1');
      expect(result.productName, 'Semi-skimmed milk');
    });

    test('asks only for the fields it uses', () async {
      final client = _StubClient(200, _hit());
      await OpenFoodFactsLookup(client: client).byBarcode('123');
      // The full product record is enormous; a phone connection should not
      // carry it.
      expect(client.lastUrl!.queryParameters['fields'], isNotNull);
      expect(client.lastUrl!.path, contains('123'));
    });

    test('identifies the app, as the service asks clients to', () async {
      final client = _StubClient(200, _hit());
      await OpenFoodFactsLookup(client: client).byBarcode('123');
      expect(client.lastHeaders['User-Agent'], contains('ShelfLife'));
    });
  });

  group('categories', () {
    Future<FoodCategory?> categoryFor(List<String> tags) async {
      final client = _StubClient(200, _hit(tags: tags));
      return (await OpenFoodFactsLookup(client: client).byBarcode('1'))
          .category;
    }

    test('frozen wins over what the food actually is', () async {
      // How it is stored dominates how long it keeps, so a frozen vegetable is
      // frozen, not a vegetable.
      expect(await categoryFor(['en:frozen-vegetables', 'en:vegetables']),
          FoodCategory.frozen);
    });

    test('maps the common groups', () async {
      expect(await categoryFor(['en:cheeses']), FoodCategory.dairy);
      expect(await categoryFor(['en:fresh-fruits']), FoodCategory.fruits);
      expect(await categoryFor(['en:cereals-and-potatoes']),
          FoodCategory.pantry);
      expect(await categoryFor(['en:spices']), FoodCategory.pantry);
    });

    test('gives up rather than guessing', () async {
      // A wrong category produces a wrong shelf life, which is worse than
      // letting the user pick.
      expect(await categoryFor(['en:some-taxonomy-branch-we-do-not-know']),
          isNull);
    });
  });

  group('a miss', () {
    test('404 is a normal not-found, not a fault', () async {
      final result = await OpenFoodFactsLookup(client: _StubClient(404, ''))
          .byBarcode('000');
      expect(result.found, isFalse);
      expect(result.source, ProductSource.notFound);
    });

    test('status 0 means they do not have the barcode', () async {
      final body = jsonEncode({'status': 0, 'status_verbose': 'not found'});
      final result = await OpenFoodFactsLookup(client: _StubClient(200, body))
          .byBarcode('000');
      expect(result.source, ProductSource.notFound);
    });

    test('a record with no usable name is a miss, not a blank hit', () async {
      // Otherwise the review screen shows an empty row the user cannot
      // interpret.
      final body = jsonEncode({
        'status': 1,
        'product': {'brands': 'Someone', 'quantity': '500 g'},
      });
      final result = await OpenFoodFactsLookup(client: _StubClient(200, body))
          .byBarcode('1');
      expect(result.found, isFalse);
    });

    test('malformed JSON does not throw into the UI', () async {
      final result =
          await OpenFoodFactsLookup(client: _StubClient(200, 'not json'))
              .byBarcode('1');
      expect(result.found, isFalse);
      expect(result.source, ProductSource.offline);
    });

    test('a slow response times out rather than hanging the scanner',
        () async {
      // The user is holding a packet up to the camera. A thirty-second wait is
      // nearly as bad as no answer.
      final client = _StubClient(200, _hit(),
          delay: const Duration(milliseconds: 300));
      final result = await OpenFoodFactsLookup(
        client: client,
        timeout: const Duration(milliseconds: 50),
      ).byBarcode('1');

      expect(result.found, isFalse);
      expect(result.source, ProductSource.offline,
          reason: 'a timeout is indistinguishable from being offline, and the '
              'user-facing consequence is the same');
    });
  });
}
