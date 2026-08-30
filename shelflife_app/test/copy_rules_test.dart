// PRD 4.10 and Principle 3, enforced over every string literal in lib/.
//
// This is a source-scanning test rather than a per-screen assertion on purpose:
// a rule checked screen by screen is a rule that the fifty-third screen breaks.
// Scanning the tree means a new screen is covered the moment it is written.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Words PRD 4.10 forbids in user-facing copy, with the reason and the
/// substitution the product uses instead.
const _forbidden = {
  'error': 'say what happened and what to do — "That did not go through"',
  'expired': 'nothing is "expired"; it is "best used today" or past that',
  'failed': 'a thing that did not happen is not a failure — "did not go '
      'through"',
  'warning': 'amber state, not a warning',
  'delete': 'BR-02 is a hard removal, but the word is "take off the list"',
};

/// Guilt framing. Principle 3: count rescues, never waste.
const _guilt = ['wasted', 'you threw', 'you wasted', 'thrown away by you'];

void main() {
  final lib = Directory('lib');

  test('lib/ exists so the scan is meaningful', () {
    // Without this, a wrong working directory would make every assertion below
    // pass vacuously.
    expect(lib.existsSync(), isTrue,
        reason: 'run from the package root');
    expect(_stringsIn(lib).length, greaterThan(300),
        reason: 'far too few strings found — the extractor is not working');
  });

  test('no forbidden word appears in user-facing copy', () {
    final hits = <String>[];
    for (final entry in _stringsIn(lib)) {
      final lower = entry.text.toLowerCase();
      for (final word in _forbidden.keys) {
        if (!_containsWord(lower, word)) continue;
        // Framework and API surface is not user-facing copy: `errorBuilder`,
        // `onError`, an SQL column name. Only prose is in scope.
        if (!_looksLikeProse(entry.text)) continue;
        hits.add('${entry.file}: "${entry.text}" contains "$word" — '
            '${_forbidden[word]}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no guilt framing about waste', () {
    final hits = <String>[];
    for (final entry in _stringsIn(lib)) {
      final lower = entry.text.toLowerCase();
      for (final phrase in _guilt) {
        if (lower.contains(phrase)) {
          hits.add('${entry.file}: "${entry.text}" contains "$phrase"');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no green "Fresh" label — fresh is silence (D4)', () {
    final hits = <String>[];
    for (final entry in _stringsIn(lib)) {
      final t = entry.text.trim();
      if (t == 'Fresh' || t == 'Still fresh' || t == 'Fresh!') {
        hits.add('${entry.file}: "$t"');
      }
    }
    expect(hits, isEmpty,
        reason: 'A fresh item carries no badge. ${hits.join('\n')}');
  });

  test('the match score is never rendered', () {
    // The scorer's `score` may be read, but never interpolated into a string
    // the user sees. `matchLabel` is the sanctioned rendering.
    final hits = <String>[];
    for (final entry in _stringsIn(lib)) {
      if (RegExp(r'\$\{?\w*[Ss]core').hasMatch(entry.text)) {
        hits.add('${entry.file}: "${entry.text}"');
      }
    }
    expect(hits, isEmpty,
        reason: 'Show "N of M ingredients", never the score. '
            '${hits.join('\n')}');
  });
}

class _Str {
  const _Str(this.file, this.text);

  final String file;
  final String text;
}

/// Extracts single-quoted Dart string literals, skipping comment lines.
///
/// Deliberately simple: it over-collects (identifiers, asset paths) rather than
/// under-collects, and [_looksLikeProse] filters afterwards. An extractor that
/// missed strings would make this whole file decorative.
List<_Str> _stringsIn(Directory dir) {
  final out = <_Str>[];
  for (final f in dir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final rawLine in f.readAsLinesSync()) {
      final line = rawLine.trimLeft();
      if (line.startsWith('//') || line.startsWith('///')) continue;
      for (final m in RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(rawLine)) {
        out.add(_Str(f.path, m.group(1)!));
      }
    }
  }
  return out;
}

/// True when a string reads as a sentence shown to a person, rather than an
/// identifier, path or key.
bool _looksLikeProse(String s) {
  if (s.length < 4) return false;
  if (!s.contains(' ')) return false; // errorBuilder, expiry_source
  if (s.startsWith('assets/') || s.startsWith('package:')) return false;
  if (s.contains('/') && !s.contains(' /')) return false;
  return true;
}

/// Whole-word match, so "Coriander" does not trip on "error" and
/// "unrecognised" does not trip on "error" either.
bool _containsWord(String haystack, String word) =>
    RegExp('\\b$word\\b').hasMatch(haystack);
