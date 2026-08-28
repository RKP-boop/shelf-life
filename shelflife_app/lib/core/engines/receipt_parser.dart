// Receipt parsing — FR-03, spec §5.3.
//
// Takes raw OCR text and produces reviewable line items. Pure: the OCR itself
// lives behind OcrService, so this is testable against fixture text with no
// camera and no device.
//
// Design stance: never guess. Below the confidence threshold an item is still
// returned, flagged `needsInput`, so screen 17 can show "Needs your input"
// rather than silently adding the wrong thing to someone's kitchen.

/// One line the user will review and can edit before saving.
class ParsedItem {
  ParsedItem({
    required this.rawName,
    required this.canonicalName,
    required this.quantity,
    this.unit,
    this.priceInr,
  });

  /// What the receipt said, kept for display — the user recognises "Amul Taaza"
  /// more readily than "milk".
  final String rawName;

  /// The resolved catalogue name, or null when nothing matched confidently.
  final String? canonicalName;

  final int quantity;
  final String? unit;
  final double? priceInr;

  bool get needsInput => canonicalName == null;
}

class ParsedReceipt {
  const ParsedReceipt({required this.items, required this.skippedLines});

  final List<ParsedItem> items;

  /// Lines the parser rejected as non-grocery. Kept so a debug view can show
  /// what was dropped rather than leaving it invisible.
  final List<String> skippedLines;

  int get needsInputCount => items.where((i) => i.needsInput).length;
}

class ReceiptParser {
  const ReceiptParser({required this.aliases});

  /// alias -> canonical name. In the app this is the 153-row seeded table.
  final Map<String, String> aliases;

  // ---------------------------------------------------------------- filters

  /// Lines that are never groceries. The board requires the parser to filter
  /// totals, GST and store identity — without this the review screen fills with
  /// "GRAND TOTAL" as an item.
  static final List<RegExp> _noise = [
    RegExp(r'\b(sub)?\s*total\b', caseSensitive: false),
    RegExp(r'\b(c|s|i)gst\b', caseSensitive: false),
    RegExp(r'\bgstin\b', caseSensitive: false),
    RegExp(r'\bround\s*off\b', caseSensitive: false),
    RegExp(r'\b(cash|change|card|upi|paid|tender)\b', caseSensitive: false),
    RegExp(r'\b(invoice|bill\s*no|receipt\s*no)\b', caseSensitive: false),
    RegExp(r'\bcashier\b', caseSensitive: false),
    RegExp(r'\b(tel|phone|ph|mob|customer\s*care|helpline)\b[:. ]', caseSensitive: false),
    RegExp(r'\b(thank\s*you|visit\s*again|welcome)\b', caseSensitive: false),
    RegExp(r'\b(ltd|pvt|limited|supermarts|retail|stores?)\b', caseSensitive: false),
    RegExp(r'\bshop\s*no\b', caseSensitive: false),
    RegExp(r'\bdate\b\s*[:.]', caseSensitive: false),
    RegExp(r'^\s*[-=*_]{3,}\s*$'),
    // a bare PIN code line such as "PUNE - 411014"
    RegExp(r'^[A-Za-z .]+[-–]\s*\d{6}\s*$'),
    // a line that is only digits, punctuation and currency
    RegExp(r'^[\s\d.,:/₹%-]+$'),
  ];

  /// Known store names. Kept separate from [_noise] so it is obvious this list
  /// is data to extend, not logic.
  static final RegExp _storeNames = RegExp(
    r'^\s*(dmart|d-mart|big\s*bazaar|reliance\s*(fresh|smart)|more|spencers|'
    r'star\s*bazaar|nature.?s\s*basket|zepto|blinkit|instamart)\s*$',
    caseSensitive: false,
  );

  // ------------------------------------------------------------- extraction

  /// Trailing "  2  132.00" — quantity then price.
  static final RegExp _qtyPrice = RegExp(r'\s+(\d{1,3})\s+(\d+[.,]\d{2})\s*$');

  /// Trailing bare price.
  static final RegExp _priceOnly = RegExp(r'\s+₹?\s*(\d+[.,]\d{2})\s*$');

  /// Pack sizes: 5KG, 250 g, 1L, 0.25kg, (250 GM), 375G
  static final RegExp _packSize = RegExp(
    r'[\s(]*\b\d+(?:[.,]\d+)?\s*(kg|kgs|g|gm|gms|gram|grams|l|ltr|litre|liter|ml|pcs|pc|pack|packs|dozen|no)\b\)?',
    caseSensitive: false,
  );

  static final RegExp _multiSpace = RegExp(r'\s{2,}');

  bool _isNoise(String line) {
    final t = line.trim();
    if (t.isEmpty) return true;
    if (_storeNames.hasMatch(t)) return true;
    for (final r in _noise) {
      if (r.hasMatch(t)) return true;
    }
    // an all-caps line with no digits and several words is usually an address
    // or a banner rather than an item
    if (!RegExp(r'\d').hasMatch(t) &&
        t == t.toUpperCase() &&
        t.split(RegExp(r'\s+')).length >= 4) {
      return true;
    }
    return false;
  }

  /// Resolve a cleaned name against the alias table.
  ///
  /// Longest alias first, so "amul taaza" wins over "milk" when both appear —
  /// the more specific match is the more informative one.
  String? _resolve(String cleaned) {
    final hay = cleaned.toLowerCase();
    if (aliases.containsKey(hay)) return aliases[hay];

    final keys = aliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final alias in keys) {
      if (alias.length < 3) continue;
      if (RegExp(r'\b' + RegExp.escape(alias) + r'\b').hasMatch(hay)) {
        return aliases[alias];
      }
    }
    return null;
  }

  /// Parse one line, or null when it is not a grocery row.
  ParsedItem? parseLine(String raw) {
    if (_isNoise(raw)) return null;

    var work = raw.trim();
    int quantity = 1;
    double? price;

    final qp = _qtyPrice.firstMatch(work);
    if (qp != null) {
      quantity = int.tryParse(qp.group(1)!) ?? 1;
      price = double.tryParse(qp.group(2)!.replaceAll(',', '.'));
      work = work.substring(0, qp.start);
    } else {
      final p = _priceOnly.firstMatch(work);
      if (p != null) {
        price = double.tryParse(p.group(1)!.replaceAll(',', '.'));
        work = work.substring(0, p.start);
      }
    }

    final display = work.replaceAll(_multiSpace, ' ').trim();
    if (display.isEmpty) return null;

    // A row with no letters left is not an item.
    if (!RegExp(r'[A-Za-z]{3,}').hasMatch(display)) return null;

    final cleaned = display
        .replaceAll(_packSize, ' ')
        .replaceAll(RegExp(r'[()]'), ' ')
        .replaceAll(_multiSpace, ' ')
        .trim();

    return ParsedItem(
      rawName: display,
      canonicalName: _resolve(cleaned),
      quantity: quantity,
      priceInr: price,
    );
  }

  /// Parse a whole receipt.
  ParsedReceipt parse(String text) {
    final items = <ParsedItem>[];
    final skipped = <String>[];

    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final item = parseLine(line);
      if (item == null) {
        skipped.add(line.trim());
      } else {
        items.add(item);
      }
    }

    return ParsedReceipt(items: items, skippedLines: skipped);
  }
}
