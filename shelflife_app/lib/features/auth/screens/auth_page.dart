// Sign-in and sign-up, wired to AppState.
//
// One widget used from two places: the welcome screen before the shell exists,
// and the profile tab afterwards. An earlier pass had a near-identical copy in
// each, which is exactly how the two drift — one gains a fix the other does
// not.

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import 'auth_screens.dart';

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
      navigator.pushReplacement<void, void>(MaterialPageRoute(
        builder: (c) => CheckEmailScreen(
          email: email,
          onBack: () => Navigator.of(c).pop(),
          onOpenMail: () => Navigator.of(c).pop(),
          onResend: () => app.resendConfirmation(email),
        ),
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
