// The advice given when Google sign-in fails.
//
// Worth its own file because the mapping is the only thing standing between a
// real cause and a shrug. It was previously unreachable from any test: the
// method that held it returns early when there is no Supabase client, and the
// offline fakes have none.

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/app/app_scope.dart';
import 'package:shelflife_app/core/services/capabilities.dart';

void main() {
  test('a misconfigured build is never told to retry', () {
    // The regression. clientConfigurationError and providerConfigurationError
    // are what an unregistered signing certificate looks like from the plugin,
    // and folding them into `refused` told people to try again when no number
    // of attempts could ever succeed.
    final advice = googleSignInProblem(GoogleAuthOutcome.misconfigured)!;
    expect(advice, contains('certificate'),
        reason: 'names the cause precisely enough to act on');
    expect(advice, isNot(contains('another go')),
        reason: 'retrying cannot register a certificate');
  });

  test('a refused attempt is the one worth retrying', () {
    expect(googleSignInProblem(GoogleAuthOutcome.refused),
        contains('another go'));
  });

  test('backing out of the picker says nothing at all', () {
    expect(googleSignInProblem(GoogleAuthOutcome.cancelled), isNull);
  });

  test('nothing offers email as a fallback', () {
    // Email sign-up was removed. Advice that points at it sends people to a
    // screen that no longer exists.
    for (final outcome in GoogleAuthOutcome.values) {
      final advice = googleSignInProblem(outcome);
      if (advice == null) continue;
      expect(advice.toLowerCase(), isNot(contains('password')));
      expect(advice.toLowerCase(), isNot(contains('email')));
    }
  });

  test('every failing outcome gets its own sentence', () {
    // Two outcomes sharing a sentence means one of them is not really being
    // reported, which is exactly how the bug above survived.
    final seen = <String>{};
    for (final outcome in GoogleAuthOutcome.values) {
      final advice = googleSignInProblem(outcome);
      if (outcome == GoogleAuthOutcome.cancelled) {
        expect(advice, isNull);
        continue;
      }
      expect(advice, isNotNull, reason: '\$outcome must say something');
      expect(seen.add(advice!), isTrue,
          reason: '\$outcome reuses another outcome sentence');
    }
    expect(seen, hasLength(GoogleAuthOutcome.values.length - 1));
  });
}
