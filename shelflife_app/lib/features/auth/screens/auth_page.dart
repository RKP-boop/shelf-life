// Sign-in and sign-up, wired to AppState.
//
// One widget used from two places: the welcome screen before the shell exists,
// and the profile tab afterwards. An earlier pass had a near-identical copy in
// each, which is exactly how the two drift — one gains a fix the other does
// not.

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import 'auth_screens.dart';
import 'verify_email_screen.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.mode});

  final CredentialsMode mode;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late CredentialsMode _mode = widget.mode;
  bool _busy = false;
  String? _problem;

  Future<void> _submit(String email, String password, String? name) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);

    setState(() {
      _busy = true;
      _problem = null;
    });

    final problem = _mode == CredentialsMode.signUp
        ? await app.signUp(email: email, password: password, name: name)
        : await app.signIn(email: email, password: password);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
    if (problem != null) return;

    // The navigator was captured before the await, so nothing here reaches
    // through a BuildContext that may have been disposed while the request was
    // in flight.
    if (_mode == CredentialsMode.signUp) {
      // A code, not a link: with no App Link configured, tapping a link in the
      // email confirms the account in a browser and the app never finds out.
      navigator.pushReplacement<void, void>(MaterialPageRoute(
        builder: (_) => _VerifyEmailRoute(email: email),
      ));
    } else {
      navigator.pop();
    }
  }

  /// Google and email share the busy flag and the problem line: only one can
  /// be in flight, and a message from either belongs in the same place.
  Future<void> _google() async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await app.signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
    if (problem == null && app.isSignedIn) navigator.pop();
  }

  @override
  Widget build(BuildContext context) => CredentialsScreen(
        mode: _mode,
        busy: _busy,
        problem: _problem,
        showGoogle: AppScope.of(context).canSignInWithGoogle,
        onGoogle: _google,
        onBack: () => Navigator.of(context).pop(),
        onSwitchMode: () => setState(() {
          _mode = _mode == CredentialsMode.signIn
              ? CredentialsMode.signUp
              : CredentialsMode.signIn;
          _problem = null;
        }),
        onSubmit: _submit,
      );
}

/// Owns the verify step's own busy and problem state, so a wrong code does not
/// have to travel back through the credentials screen.
class _VerifyEmailRoute extends StatefulWidget {
  const _VerifyEmailRoute({required this.email});

  final String email;

  @override
  State<_VerifyEmailRoute> createState() => _VerifyEmailRouteState();
}

class _VerifyEmailRouteState extends State<_VerifyEmailRoute> {
  bool _busy = false;
  String? _problem;

  Future<void> _verify(String code) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem =
        await app.verifyEmailCode(email: widget.email, code: code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
    // On success the gate swaps the welcome screen for the shell on its own;
    // popping just clears this route off the stack.
    if (problem == null) navigator.pop();
  }

  @override
  Widget build(BuildContext context) => VerifyEmailScreen(
        email: widget.email,
        // Sign-up just sent one. Offering "send it again" immediately invites
        // three taps and three codes, of which only the last works.
        resendCooldown: const Duration(seconds: 60),
        busy: _busy,
        problem: _problem,
        onVerify: _verify,
        onResend: () =>
            AppScope.read(context).resendConfirmation(widget.email),
        onBack: () => Navigator.of(context).pop(),
        onWrongEmail: () => Navigator.of(context).pop(),
      );
}
