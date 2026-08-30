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
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'or'});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(child: Divider(color: T.structureDivider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(label,
                style: T.labelMedium12.copyWith(color: T.textSecondary)),
          ),
          const Expanded(child: Divider(color: T.structureDivider)),
        ],
      );
}

// ------------------------------------------------------------------ 04

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    this.onCreateAccount,
    this.onSignIn,
    this.onGuest,
    this.onGoogle,
    this.showGoogle = false,
    this.googleBusy = false,
    this.problem,
  });

  final VoidCallback? onCreateAccount;
  final VoidCallback? onSignIn;
  final VoidCallback? onGuest;
  final VoidCallback? onGoogle;

  /// Hidden when the build has no OAuth client id. An option that cannot work
  /// is worse than no option.
  final bool showGoogle;

  final bool googleBusy;

  /// Surfaced here because Google sign-in can fail on this screen, before any
  /// form exists to attach a message to.
  final String? problem;

  @override
  Widget build(BuildContext context) => AppScreen(
        scrollable: false,
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Center(
                child: ArtHalo(
                  size: 200,
                  child: ProduceImage(glyphKey: 'avocado', size: 142),
                ),
              ),
              const Spacer(flex: 2),
              const ScreenTitle(
                ['Your kitchen,', 'kept in mind'],
                subtitle: 'Create an account to keep your kitchen across '
                    'devices, or start straight away and sign up later.',
              ),
              const Spacer(flex: 2),
              if (showGoogle) ...[
                GoogleButton(onPressed: onGoogle, busy: googleBusy),
                const SizedBox(height: 16),
                const OrDivider(),
                const SizedBox(height: 16),
              ],
              AppButton(
                label: 'Create an account',
                onPressed: onCreateAccount,
              ),
              const SizedBox(height: 12),
              AppButton.secondary(label: 'Sign in', onPressed: onSignIn),
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
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------ 05, 06

/// One screen for both sign-in and sign-up. The two differ by a single field
/// and the button copy; two files would drift.
class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({
    super.key,
    required this.mode,
    this.onBack,
    this.onSubmit,
    this.onSwitchMode,
    this.onForgotPassword,
    this.onGoogle,
    this.showGoogle = false,
    this.busy = false,
    this.problem,
  });

  final CredentialsMode mode;
  final VoidCallback? onBack;
  final void Function(String email, String password, String? name)? onSubmit;
  final VoidCallback? onSwitchMode;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onGoogle;

  /// Hidden when the build has no OAuth client id.
  final bool showGoogle;

  final bool busy;

  /// A recoverable problem, phrased as what to do next. Never the word the PRD
  /// forbids — "That password does not match", not "Error".
  final String? problem;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

enum CredentialsMode { signUp, signIn }

class _CredentialsScreenState extends State<CredentialsScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isSignUp => widget.mode == CredentialsMode.signUp;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: widget.onBack),
              const SizedBox(height: 16),
              ScreenTitle(
                _isSignUp
                    ? const ['Create your', 'account']
                    : const ['Welcome', 'back'],
                subtitle: _isSignUp
                    ? 'Your kitchen syncs across every device you sign in on.'
                    : 'Sign in and your kitchen comes back exactly as it was.',
              ),
              const SizedBox(height: 28),
              if (_isSignUp) ...[
                AppTextField(
                  label: 'Your name',
                  hint: 'Rakesh',
                  controller: _name,
                  icon: Icons.person_outline,
                  helper: 'Only used to greet you on the home screen.',
                ),
                const SizedBox(height: 18),
              ],
              AppTextField(
                label: 'Email',
                hint: 'you@example.com',
                controller: _email,
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 18),
              AppTextField(
                label: 'Password',
                hint: _isSignUp ? 'At least 8 characters' : null,
                controller: _password,
                icon: Icons.lock_outline,
                obscure: true,
                helper: _isSignUp
                    ? 'Eight characters or more. A phrase is easier to '
                        'remember than a jumble.'
                    : null,
              ),
              if (!_isSignUp) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onForgotPassword,
                    child: Text('Forgot your password?',
                        style:
                            T.labelMedium12.copyWith(color: T.accentPrimary)),
                  ),
                ),
              ],
              if (widget.problem != null) ...[
                const SizedBox(height: 18),
                _ProblemStrip(widget.problem!),
              ],
              const SizedBox(height: 28),
              AppButton(
                label: widget.busy
                    ? 'One moment'
                    : _isSignUp
                        ? 'Create account'
                        : 'Sign in',
                onPressed: widget.busy
                    ? null
                    : () => widget.onSubmit?.call(
                          _email.text.trim(),
                          _password.text,
                          _isSignUp ? _name.text.trim() : null,
                        ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: widget.onSwitchMode,
                  child: Text.rich(
                    TextSpan(
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary),
                      children: [
                        TextSpan(
                            text: _isSignUp
                                ? 'Already have an account?  '
                                : 'New here?  '),
                        TextSpan(
                          text: _isSignUp ? 'Sign in' : 'Create an account',
                          style: T.labelMedium12
                              .copyWith(color: T.accentPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

/// A problem the user can act on. Amber rather than red: nothing has broken,
/// something needs a correction.
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

// ------------------------------------------------------------------ 07

class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({
    super.key,
    required this.email,
    this.onOpenMail,
    this.onResend,
    this.onBack,
    this.resent = false,
  });

  final String email;
  final VoidCallback? onOpenMail;
  final VoidCallback? onResend;
  final VoidCallback? onBack;
  final bool resent;

  @override
  Widget build(BuildContext context) => AppScreen(
        scrollable: false,
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const Spacer(flex: 2),
              Center(
                child: ArtHalo(
                  size: 190,
                  child: Icon(Icons.mark_email_unread_outlined,
                      size: 92, color: T.accentPrimary),
                ),
              ),
              const Spacer(),
              const ScreenTitle(['Check your', 'email']),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: T.bodyRegular14.copyWith(color: T.textSecondary),
                  children: [
                    const TextSpan(text: 'We sent a confirmation link to '),
                    TextSpan(
                        text: email,
                        style: T.bodyRegular14
                            .copyWith(color: T.textPrimary)
                            .copyWith(fontWeight: FontWeight.w600)),
                    const TextSpan(
                        text: '. Open it and you are in. You can keep using '
                            'the app in the meantime.'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const InfoStrip(
                'Not there after a minute? Have a look in your spam folder — '
                'confirmation mail often lands there the first time.',
              ),
              const Spacer(flex: 2),
              AppButton(label: 'Open my email', onPressed: onOpenMail),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: resent ? null : onResend,
                  child: Text(
                    resent ? 'Link sent again' : 'Send the link again',
                    style: T.labelMedium12.copyWith(
                        color: resent ? T.textSecondary : T.accentPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------ 08

class GuestModeScreen extends StatelessWidget {
  const GuestModeScreen({
    super.key,
    this.onContinue,
    this.onCreateAccount,
    this.onBack,
  });

  final VoidCallback? onContinue;
  final VoidCallback? onCreateAccount;
  final VoidCallback? onBack;

  /// Stated plainly and in both directions. A guest-mode screen that only lists
  /// what you lose is a nudge dressed as information.
  static const _keeps = [
    'Everything works — scanning, recipes, reminders',
    'Your kitchen is stored on this phone',
    'You can create an account later and keep what you added',
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
              const SizedBox(height: 12),
              AppButton.secondary(
                  label: 'Create an account instead',
                  onPressed: onCreateAccount),
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
