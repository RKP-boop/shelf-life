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
import 'package:shelflife_app/core/widgets/app_widgets.dart';
import 'package:shelflife_app/features/auth/screens/auth_screens.dart';
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

  testWidgets('08 guest mode', (tester) async {
    await pumpScreen(
        tester, const GuestModeScreen(onBack: _noop, onGoogle: _noop));
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

  testWidgets('the Google button is absent when it cannot work', (tester) async {
    // An option that fails on tap is worse than an option that is not there.
    await pumpScreen(tester, _welcome());
    expect(find.byType(GoogleButton), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
  });

  testWidgets('guest becomes the primary action when Google cannot work',
      (tester) async {
    // Otherwise the screen has no button at all and reads as broken: with
    // email sign-up gone, guest is the only way in.
    await pumpScreen(tester, _welcome());
    expect(find.widgetWithText(AppButton, 'Start cooking'), findsOneWidget);
  });

  testWidgets('nothing offers an email or password anywhere in auth',
      (tester) async {
    // The guard on the decision this replaced. Supabase cannot send a
    // confirmation code on this project -- template editing needs custom SMTP,
    // the default template has a link and no token, and the cap is two emails
    // an hour -- so any surviving mention of email sign-up would be an offer
    // the app cannot honour.
    for (final screen in [
      _welcome(showGoogle: true),
      _welcome(),
      const GuestModeScreen(onBack: _noop, onGoogle: _noop),
    ]) {
      await pumpScreen(tester, screen);
      expect(find.textContaining('assword'), findsNothing);
      expect(find.textContaining('Create an account'), findsNothing);
      expect(find.textContaining('Email'), findsNothing);
    }
  });

  testWidgets('a Google problem is shown on the welcome screen', (tester) async {
    await pumpScreen(
      tester,
      _welcome(
        showGoogle: true,
        problem: 'Google sign-in is not available on this phone. You can '
            'carry on without an account.',
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
      onGuest: _noop,
    );

void _noop() {}
