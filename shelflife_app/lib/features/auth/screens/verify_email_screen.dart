// Screen 07 — confirm the email with a six-digit code.
//
// This replaces the magic-link screen, and not as a preference. Supabase's
// default confirmation email carries a link, and tapping it opens a browser:
// the account is confirmed but the app never learns, so it sits on "check your
// email" forever. Making that work needs an Android App Link, a verified
// domain, and an assetlinks.json file — a lot of moving parts to get someone
// back into an app they never left.
//
// A code typed into the app closes the loop without leaving it, which is also
// the pattern most people in India already expect from an OTP.
//
// It requires one change in Supabase: the "Confirm signup" email template must
// include {{ .Token }}. See docs/email-verification-setup.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.onVerify,
    this.onResend,
    this.onBack,
    this.onWrongEmail,
    this.busy = false,
    this.problem,
    this.resendCooldown = Duration.zero,
  });

  final String email;

  /// Called with the complete six-digit code.
  final ValueChanged<String>? onVerify;

  final Future<void> Function()? onResend;
  final VoidCallback? onBack;

  /// Lets the user correct a typo in the address without starting over — the
  /// single most likely reason no code arrives.
  final VoidCallback? onWrongEmail;

  final bool busy;
  final String? problem;

  /// How long before "send it again" becomes available. Prevents someone
  /// tapping it five times and getting five codes, of which only the last
  /// works.
  final Duration resendCooldown;

  static const digits = 6;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  // One controller behind six boxes, rather than six fields. Six fields means
  // six focus nodes and a pile of edge cases around backspace and paste; one
  // field with a painted representation gets paste and autofill for free.
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Straight to the keyboard: there is nothing else to do on this screen.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (_controller.text.length == VerifyEmailScreen.digits && !widget.busy) {
      // Submit on the sixth digit. Making someone reach for a button after
      // typing the last character of a code they just read is pure friction.
      widget.onVerify?.call(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _controller.text;

    return AppScreen(
      child: Gutter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(onBack: widget.onBack),
            const SizedBox(height: 20),
            Center(
              child: ArtHalo(
                size: 170,
                child: Icon(Icons.mark_email_unread_outlined,
                    size: 82, color: T.accentPrimary),
              ),
            ),
            const SizedBox(height: 26),
            const ScreenTitle(['Enter the code', 'we emailed you']),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: T.bodyRegular14.copyWith(color: T.textSecondary),
                children: [
                  const TextSpan(text: 'Six digits, sent to '),
                  TextSpan(
                    text: widget.email,
                    style: T.bodyRegular14.copyWith(
                      color: T.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // The real field, invisible and one logical pixel tall: it holds
            // focus, the keyboard and autofill, while the boxes below are what
            // the user sees.
            SizedBox(
              height: 1,
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  maxLength: VerifyEmailScreen.digits,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ),

            GestureDetector(
              onTap: () => _focus.requestFocus(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < VerifyEmailScreen.digits; i++)
                    _Box(
                      digit: i < code.length ? code[i] : null,
                      active: i == code.length && _focus.hasFocus,
                      wrong: widget.problem != null,
                    ),
                ],
              ),
            ),

            if (widget.problem != null) ...[
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: T.stateAmberBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 19, color: T.stateAmberText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.problem!,
                          style: T.secondaryRegular13
                              .copyWith(color: T.stateAmberText)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),
            AppButton(
              label: widget.busy ? 'Checking' : 'Confirm',
              onPressed: code.length == VerifyEmailScreen.digits && !widget.busy
                  ? () => widget.onVerify?.call(code)
                  : null,
            ),
            const SizedBox(height: 18),
            Center(
              child: _Resend(
                cooldown: widget.resendCooldown,
                onResend: widget.onResend,
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: widget.onWrongEmail,
                child: Text('Wrong address?',
                    style:
                        T.labelMedium12.copyWith(color: T.textSecondary)),
              ),
            ),
            const SizedBox(height: 20),
            const InfoStrip(
              'Nothing after a minute? Check your spam folder — confirmation '
              'mail often lands there the first time.',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.digit, required this.active, required this.wrong});

  final String? digit;
  final bool active;
  final bool wrong;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 48,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: T.cardBase,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: wrong
                ? T.stateAmberText
                : active
                    ? T.accentPrimary
                    : T.structureBorder,
            width: active || wrong ? 2 : 1.2,
          ),
        ),
        child: Text(digit ?? '', style: T.titleSemiBold18),
      );
}

/// "Send it again", with a countdown while it is on cooldown.
class _Resend extends StatefulWidget {
  const _Resend({required this.cooldown, required this.onResend});

  final Duration cooldown;
  final Future<void> Function()? onResend;

  @override
  State<_Resend> createState() => _ResendState();
}

class _ResendState extends State<_Resend> {
  late int _left = widget.cooldown.inSeconds;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (_left > 0) _tick();
  }

  Future<void> _tick() async {
    while (_left > 0 && mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _left--);
    }
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    await widget.onResend?.call();
    if (!mounted) return;
    setState(() {
      _sending = false;
      // Supabase rate-limits confirmation mail, so the cooldown is real rather
      // than decorative.
      _left = 60;
    });
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    if (_left > 0) {
      return Text('You can ask for another in ${_left}s',
          style: T.labelMedium12.copyWith(color: T.textSecondary));
    }
    return TextButton(
      onPressed: _sending ? null : _send,
      child: Text(
        _sending ? 'Sending' : 'Send it again',
        style: T.labelMedium12.copyWith(
          color: _sending ? T.textSecondary : T.accentPrimary,
        ),
      ),
    );
  }
}
