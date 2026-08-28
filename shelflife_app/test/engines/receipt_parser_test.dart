// Receipt parser — FR-03, spec §5.3.
//
// Tested against a realistic DMart receipt fixture rather than hand-picked
// lines: 12 grocery rows buried in 26 lines of header, tax and footer. The
// board is explicit that non-grocery lines must be filtered by the parser.
//
// PRD 4.14 targets fewer than 20% of scanned items needing a manual edit, so
// the fixture asserts a resolution rate, not just "it ran".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/engines/receipt_parser.dart';

/// A small alias table standing in for the seeded one (153 rows in Postgres).
const aliases = <String, String>{
  'aashirvaad atta': 'atta',
  'atta': 'atta',
  'amul taaza': 'milk',
  'toned milk': 'milk',
  'milk': 'milk',
  'palak': 'spinach',
  'spinach': 'spinach',
  'tomato': 'tomato',
  'tomato local': 'tomato',
  'onion': 'onion',
  'amul paneer': 'paneer',
  'paneer': 'paneer',
  'tata salt': 'salt',
  'salt': 'salt',
  'basmati rice': 'rice',
  'rice': 'rice',
  'dhania': 'coriander',
  'adrak': 'ginger',
  'fortune refined oil': 'cooking oil',
  'refined oil': 'cooking oil',
  'britannia brown bread': 'bread',
  'brown bread': 'bread',
  'bread': 'bread',
};

void main() {
  final parser = ReceiptParser(aliases: aliases);

  group('token stripping', () {
    test('removes trailing quantity and price columns', () {
      final line = parser.parseLine('AMUL TAAZA TONED MILK 1L   2  132.00');
      expect(line!.canonicalName, 'milk');
      expect(line.rawName, isNot(contains('132')));
    });

    test('removes pack sizes in several notations', () {
      for (final raw in [
        'FRESH PALAK 250G',
        'FRESH PALAK 250 g',
        'FRESH PALAK 0.25KG',
        'FRESH PALAK (250 GM)',
      ]) {
        expect(parser.parseLine(raw)?.canonicalName, 'spinach', reason: raw);
      }
    });

    test('reads the quantity column when present', () {
      final line = parser.parseLine('BRITANNIA BROWN BREAD      2   90.00');
      expect(line!.quantity, 2);
    });

    test('defaults quantity to one when absent', () {
      expect(parser.parseLine('FRESH PALAK 250G')!.quantity, 1);
    });
  });

  group('non-grocery filtering (explicit board requirement)', () {
    test('drops totals, tax and payment lines', () {
      for (final raw in [
        'SUB TOTAL                1548.00',
        'GRAND TOTAL              1573.00',
        'CGST @ 2.5%                12.40',
        'SGST @ 2.5%                12.40',
        'ROUND OFF                   0.20',
        'TOTAL QTY                     14',
        'CASH                     1600.00',
        'CHANGE                     27.00',
      ]) {
        expect(parser.parseLine(raw), isNull, reason: raw);
      }
    });

    test('drops store identity and contact lines', () {
      for (final raw in [
        'DMART',
        'AVENUE SUPERMARTS LTD',
        'GSTIN: 27AACCA8432H1ZM',
        'Tel: 020-49103000',
        'Customer Care: 1800-210-0000',
        'SHOP NO 5, PHOENIX MALL, VIMAN NAGAR',
        'PUNE - 411014',
      ]) {
        expect(parser.parseLine(raw), isNull, reason: raw);
      }
    });

    test('drops invoice metadata and separators', () {
      for (final raw in [
        'TAX INVOICE',
        'Bill No: 2026/07/20-88421',
        'Date: 20/07/2026 18:42',
        'Cashier: RAJESH K',
        '--------------------------------',
        '',
        'THANK YOU FOR SHOPPING',
        'VISIT AGAIN',
      ]) {
        expect(parser.parseLine(raw), isNull, reason: raw);
      }
    });
  });

  group('alias resolution (spec §3)', () {
    test('resolves Hindi and regional names', () {
      expect(parser.parseLine('FRESH PALAK 250G')?.canonicalName, 'spinach');
      expect(parser.parseLine('DHANIA 100G')?.canonicalName, 'coriander');
      expect(parser.parseLine('ADRAK 200G')?.canonicalName, 'ginger');
    });

    test('resolves brand names to the underlying ingredient', () {
      expect(parser.parseLine('AMUL TAAZA TONED MILK 1L')?.canonicalName, 'milk');
      expect(parser.parseLine('AASHIRVAAD ATTA 5KG')?.canonicalName, 'atta');
      expect(parser.parseLine('FORTUNE REFINED OIL 1L')?.canonicalName, 'cooking oil');
    });

    test('keeps the raw text for display, since the user recognises the brand', () {
      final line = parser.parseLine('AMUL TAAZA TONED MILK 1L   2  132.00')!;
      expect(line.rawName.toLowerCase(), contains('amul'));
      expect(line.canonicalName, 'milk');
    });
  });

  group('confidence (screen 17 "Needs your input")', () {
    test('an unrecognised item is returned, not dropped', () {
      final line = parser.parseLine('KELLOGGS CHOCOS 375G   1  245.00');
      expect(line, isNotNull, reason: 'the user must still be able to keep it');
      expect(line!.canonicalName, isNull);
      expect(line.needsInput, isTrue);
    });

    test('a confident match does not ask for input', () {
      expect(parser.parseLine('FRESH PALAK 250G')!.needsInput, isFalse);
    });
  });

  group('full receipt fixture', () {
    late ParsedReceipt result;

    setUpAll(() {
      final text = File('test/fixtures/receipt_dmart.txt').readAsStringSync();
      result = parser.parse(text);
    });

    test('finds exactly the twelve grocery lines', () {
      expect(result.items.length, 12);
    });

    test('resolves at least 80% of them (PRD 4.14: <20% manual edits)', () {
      final resolved = result.items.where((i) => i.canonicalName != null).length;
      expect(resolved / result.items.length, greaterThanOrEqualTo(0.8),
          reason: '$resolved of ${result.items.length} resolved');
    });

    test('no total or tax line leaked through', () {
      final leaked = result.items.where((i) =>
          RegExp(r'total|gst|cash|change|round', caseSensitive: false)
              .hasMatch(i.rawName));
      expect(leaked, isEmpty, reason: leaked.map((e) => e.rawName).join(', '));
    });

    test('picks up the multi-unit line correctly', () {
      final milk = result.items.firstWhere((i) => i.canonicalName == 'milk');
      expect(milk.quantity, 2);
    });

    test('reports a summary the review screen can show', () {
      // Screen 17's header: "Review 12 items"
      expect(result.items.length, greaterThan(0));
      expect(result.needsInputCount, lessThanOrEqualTo(2));
    });
  });
}
