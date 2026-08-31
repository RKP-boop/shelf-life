// Golden tests. Tagged so CI can skip them.
//
// Golden images are font-rasterisation dependent: the same widget renders a
// few pixels differently on Linux than on Windows, so images committed from a
// Windows machine fail on an Ubuntu runner for reasons that have nothing to do
// with the code. Flutter's own guidance is to treat goldens as valid on one
// platform only. They run locally, where they were rendered.
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shelflife_app/features/auth/screens/auth_screens.dart';
import 'package:shelflife_app/features/auth/screens/verify_email_screen.dart';
import 'package:shelflife_app/features/onboarding/screens/value_prop_screen.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // Callbacks are wired in every golden. Without them the buttons render in
  // their disabled state, and the images stop being a fair picture of what a
  // user sees.

  for (var i = 0; i < ValueProp.all.length; i++) {
    testWidgets('0${i + 1} value prop $i', (tester) async {
      await pumpScreen(tester,
          ValuePropScreen(index: i, onNext: _noop, onSkip: _noop));
      await expectLater(find.byType(ValuePropScreen),
          matchesGoldenFile('goldens/0${i + 1}-value-prop.png'));
    });
  }

  testWidgets('04 welcome', (tester) async {
    await pumpScreen(tester, _welcome());
    await expectLater(find.byType(WelcomeScreen),
        matchesGoldenFile('goldens/04-welcome.png'));
  });

  testWidgets('05 create account', (tester) async {
    await pumpScreen(
      tester,
      _credentials(CredentialsMode.signUp),
    );
    await expectLater(find.byType(CredentialsScreen),
        matchesGoldenFile('goldens/05-create-account.png'));
  });

  testWidgets('06 sign in', (tester) async {
    await pumpScreen(
      tester,
      _credentials(CredentialsMode.signIn),
    );
    await expectLater(find.byType(CredentialsScreen),
        matchesGoldenFile('goldens/06-sign-in.png'));
  });

  testWidgets('06 sign in with a recoverable problem', (tester) async {
    await pumpScreen(
      tester,
      _credentials(
        CredentialsMode.signIn,
        problem: 'That email and password do not match. Try again, or reset '
            'your password.',
      ),
    );
    await expectLater(find.byType(CredentialsScreen),
        matchesGoldenFile('goldens/06-sign-in-problem.png'));
  });

  testWidgets('07 verify email, empty', (tester) async {
    await pumpScreen(tester, _verify());
    await expectLater(find.byType(VerifyEmailScreen),
        matchesGoldenFile('goldens/07-verify-email.png'));
  });

  testWidgets('07 verify email, wrong code', (tester) async {
    await pumpScreen(
      tester,
      _verify(problem: 'That code does not match. Check the digits, or ask '
          'for a new one.'),
    );
    await expectLater(find.byType(VerifyEmailScreen),
        matchesGoldenFile('goldens/07-verify-email-wrong.png'));
  });

  testWidgets('submits on the sixth digit without a button press',
      (tester) async {
    // Reaching for a button after typing the last character of a code you just
    // read is pure friction.
    String? submitted;
    await pumpScreen(
      tester,
      VerifyEmailScreen(
        email: 'rakesh@example.com',
        onVerify: (code) => submitted = code,
        onBack: _noop,
      ),
    );
    await tester.enterText(find.byType(TextField), '12345');
    expect(submitted, isNull, reason: 'five digits is not a code yet');
    await tester.enterText(find.byType(TextField), '123456');
    expect(submitted, '123456');
  });

  testWidgets('only digits reach the code field', (tester) async {
    await pumpScreen(tester, _verify());
    await tester.enterText(find.byType(TextField), '12ab34');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1234',
      reason: 'letters would never match a numeric code',
    );
  });

  testWidgets('08 guest mode', (tester) async {
    await pumpScreen(tester, const GuestModeScreen(onBack: _noop));
    await expectLater(find.byType(GuestModeScreen),
        matchesGoldenFile('goldens/08-guest-mode.png'));
  });

  // Google sign-in is offered only when the build carries an OAuth client id,
  // so both states are worth a golden: the button present, and absent.

  testWidgets('04 welcome with Google offered', (tester) async {
    await pumpScreen(tester, _welcome(showGoogle: true));
    await expectLater(find.byType(WelcomeScreen),
        matchesGoldenFile('goldens/04-welcome-google.png'));
  });

  testWidgets('06 sign in with Google offered', (tester) async {
    await pumpScreen(
      tester,
      _credentials(CredentialsMode.signIn, showGoogle: true),
    );
    await expectLater(find.byType(CredentialsScreen),
        matchesGoldenFile('goldens/06-sign-in-google.png'));
  });

  testWidgets('the Google button is absent when it cannot work', (tester) async {
    // An option that fails on tap is worse than an option that is not there.
    await pumpScreen(tester, _welcome());
    expect(find.byType(GoogleButton), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
  });

  testWidgets('a Google problem is shown on the welcome screen', (tester) async {
    await pumpScreen(
      tester,
      _welcome(
        showGoogle: true,
        problem: 'Google sign-in is not available on this phone. You can use '
            'email and password instead.',
      ),
    );
    await expectLater(find.byType(WelcomeScreen),
        matchesGoldenFile('goldens/04-welcome-google-problem.png'));
  });
}


WelcomeScreen _welcome({bool showGoogle = false, String? problem}) =>
    WelcomeScreen(
      showGoogle: showGoogle,
      problem: problem,
      onGoogle: _noop,
      onCreateAccount: _noop,
      onSignIn: _noop,
      onGuest: _noop,
    );

CredentialsScreen _credentials(
  CredentialsMode mode, {
  bool showGoogle = false,
  String? problem,
}) =>
    CredentialsScreen(
      mode: mode,
      showGoogle: showGoogle,
      problem: problem,
      onBack: _noop,
      onGoogle: _noop,
      onSubmit: (_, _, _) {},
      onSwitchMode: _noop,
      onForgotPassword: _noop,
    );

VerifyEmailScreen _verify({String? problem}) => VerifyEmailScreen(
      email: 'rakesh@example.com',
      problem: problem,
      onVerify: (_) {},
      onBack: _noop,
      onWrongEmail: _noop,
    );

void _noop() {}
