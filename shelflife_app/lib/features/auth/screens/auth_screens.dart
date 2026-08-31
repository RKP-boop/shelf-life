// Screens 04–08 — the auth group.
//
// 04 Welcome chooser · 05 Create account · 06 Sign in · 07 Check your email ·
// 08 Guest mode explainer.
//
// Guest mode is a first-class path, not a dark-pattern afterthought: the PRD
// requires the app to be usable without an account, and screen 08 says plainly
// what is lost. The sync queue supports this directly — guest mode queues
// nothing, and `rekey()` moves local rows onto a real user id on upgrade.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/produce_image.dart';


/// "Continue with Google".
///
/// No Google logo. Their branding guidelines require the official asset, and
/// an approximated mark is both inaccurate and — tested at 20dp — an
/// unreadable coloured blob. A clean typographic button is honest; the mark
/// can be dropped in later without touching this layout.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
        color: T.cardBase,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: T.structureBorder, width: 1.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: T.textSecondary),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  busy ? 'One moment' : 'Continue with Google',
                  style: T.cardSemiBold15.copyWith(
                    color: busy ? T.textSecondary : T.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A rule with a word in it, separating the two ways in.
// ------------------------------------------------------------------ 04

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    this.onGuest,
    this.onGoogle,
    this.showGoogle = false,
    this.googleBusy = false,
    this.problem,
  });

  final VoidCallback? onGuest;
  final VoidCallback? onGoogle;

  /// False when the build carries no OAuth client id, and then Google is not
  /// offered at all: an option that cannot work is worse than no option. With
  /// email sign-up gone this also means guest is the only way in, so the guest
  /// action is promoted to the primary button rather than staying a footnote.
  ///
  /// Why email sign-up is gone: the Supabase project cannot send a
  /// confirmation code. Template editing is gated behind custom SMTP, the
  /// default template carries a link and no token, and the project-wide send
  /// limit is two emails an hour. An email flow built on that would fail for
  /// the third person to try it, so Google -- which sends no email -- is the
  /// only account path.
  final bool showGoogle;

  final bool googleBusy;

  /// Surfaced here because Google sign-in can fail on this screen, and there
  /// is no form left to attach a message to.
  final String? problem;

  @override
  Widget build(BuildContext context) => AppScreen(
        scrollable: false,
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 3),
              Center(
                child: ArtHalo(
                  size: 200,
                  child: ProduceImage(glyphKey: 'avocado', size: 142),
                ),
              ),
              // Deliberately uneven: 3 above the art, 2 above the title, 1
              // above the action. Removing two of this screen's three buttons
              // left a void between the copy and the button, and an even split
              // put the action adrift from the sentence that motivates it.
              const Spacer(flex: 2),
              ScreenTitle(
                const ['Your kitchen,', 'kept in mind'],
                subtitle: showGoogle
                    ? 'Sign in with Google to keep your kitchen on every '
                        'device you use, or start straight away and stay on '
                        'this phone.'
                    : 'Your kitchen is kept on this phone. Everything works '
                        'the same way; it just does not follow you to another '
                        'device.',
              ),
              const Spacer(),
              if (showGoogle) ...[
                GoogleButton(onPressed: onGoogle, busy: googleBusy),
                if (problem != null) ...[
                  const SizedBox(height: 16),
                  _ProblemStrip(problem!),
                ],
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: onGuest,
                    child: Text(
                      'Continue without an account',
                      style: T.labelMedium12.copyWith(color: T.accentPrimary),
                    ),
                  ),
                ),
              ] else
                // Guest is the only way in, so it carries the primary button.
                // A screen whose only action is a text link reads as broken.
                AppButton(label: 'Start cooking', onPressed: onGuest),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
}

class _ProblemStrip extends StatelessWidget {
  const _ProblemStrip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: T.stateAmberBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 19, color: T.stateAmberText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: T.secondaryRegular13
                      .copyWith(color: T.stateAmberText)),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 08

class GuestModeScreen extends StatelessWidget {
  const GuestModeScreen({
    super.key,
    this.onContinue,
    this.onGoogle,
    this.onBack,
  });

  final VoidCallback? onContinue;

  /// Null when the build has no OAuth client id, which hides the row: there is
  /// then no alternative to offer.
  final VoidCallback? onGoogle;

  final VoidCallback? onBack;

  /// Stated plainly and in both directions. A guest-mode screen that only lists
  /// what you lose is a nudge dressed as information.
  static const _keeps = [
    'Everything works — scanning, recipes, reminders',
    'Your kitchen is stored on this phone',
    'You can sign in later and keep everything you added',
  ];

  static const _loses = [
    'Nothing syncs to another device',
    'Clearing the app removes your kitchen',
  ];

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const SizedBox(height: 16),
              const ScreenTitle(
                ['Starting without', 'an account'],
                subtitle: 'Worth knowing before you go ahead.',
              ),
              const SizedBox(height: 24),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in _keeps) _row(line, true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in _loses) _row(line, false),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              AppButton(label: 'Continue this way', onPressed: onContinue),
              if (onGoogle != null) ...[
                const SizedBox(height: 12),
                AppButton.secondary(
                  label: 'Sign in with Google instead',
                  onPressed: onGoogle,
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      );

  static Widget _row(String text, bool included) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              included ? Icons.check_circle_outline : Icons.remove_circle_outline,
              size: 19,
              color: included ? T.accentPrimary : T.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: T.bodyRegular14)),
          ],
        ),
      );
}
