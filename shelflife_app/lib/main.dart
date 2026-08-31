// Bootstrap.
//
// Order matters and is not arbitrary:
//
//   1. Hive first. It is the source of truth, and every screen reads from it
//      synchronously — nothing can render before it is open.
//   2. Seed the reference data on first run. The catalogue, aliases, recipes
//      and barcode cache ship with the app rather than being fetched, because
//      a first-run user with no connection still has to get a working product
//      (Principle 6, and D1 for barcodes specifically).
//   3. Supabase last, and never blocking. If it is slow or unreachable the app
//      still starts; it just queues what it writes.
//
// The anon key is compiled in via --dart-define. It is a publishable key and
// RLS is what actually protects the data. The service-role key must never
// appear here, in the repo, or in the APK.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_scope.dart';
import 'app/shell.dart';
import 'core/services/platform_capabilities.dart';
import 'core/theme/app_theme.dart';
import 'database/local_store.dart';
import 'database/sync_queue.dart';
import 'features/auth/screens/auth_page.dart';
import 'features/auth/screens/auth_screens.dart';
import 'features/onboarding/screens/value_prop_screen.dart';
import 'services/product_lookup.dart';
import 'services/reminder_service.dart';
import 'services/seed.dart';
import 'services/sync_service.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // Anything thrown between here and runApp kills the process before a single
  // frame exists, and the user sees the app open and vanish with nothing to
  // report. Catching it means they get a screen that says what happened —
  // which is also the only way the failure is diagnosable on someone else's
  // phone.
  try {
    runApp(ShelfLifeApp(state: await _bootstrap()));
  } catch (e, stack) {
    debugPrint('ShelfLife could not start: $e\n$stack');
    runApp(_StartupFailureApp(detail: '$e'));
  }
}

Future<AppState> _bootstrap() async {
  final store = LocalStore.instance;
  await store.init();
  await Seed.ensure(store);

  final client = await _initSupabase();

  final capabilities = await platformCapabilities();
  final queue = SyncQueue(store);
  final sync = SyncService(
    queue: queue,
    store: store,
    connectivity: capabilities.connectivity,
    client: client,
  );
  final reminders = ReminderService(
    scheduler: capabilities.notifications,
    store: store,
  );

  final state = AppState(
    store: store,
    queue: queue,
    sync: sync,
    capabilities: capabilities,
    reminders: reminders,
    productLookup: OpenFoodFactsLookup(),
  );

  // Restore an existing session before the first frame, so a signed-in user
  // never sees the welcome screen flash past.
  final session = client?.auth.currentSession;
  if (session != null) {
    await store.meta.put('user_id', session.user.id);
    await store.meta.put('is_guest', false);
    await store.meta.put('email', session.user.email);
  }

  // Not awaited: the first frame must not wait on connectivity or a drain.
  unawaited(sync.start());

  return state;
}

/// Shown when bootstrap threw. Deliberately built from nothing but Flutter
/// primitives and literal colours: whatever failed may well be the theme, the
/// fonts or the asset bundle, and a failure screen that depends on those has
/// nothing to say when it matters most.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFFDF4EC),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_off_outlined,
                      size: 64, color: Color(0xFF9A5B00)),
                  const SizedBox(height: 24),
                  const Text(
                    'ShelfLife could not start',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF12211B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Something went wrong setting up on this phone. '
                    'Reopening it is worth a try. If it keeps happening, the '
                    'detail below is what to send on.',
                    style: TextStyle(fontSize: 14, color: Color(0xFF5C6B64)),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Color(0xFF9A5B00),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Returns null when there is no backend configured or it could not be
/// reached. Both are supported states — the app runs against Hive and queues
/// anything it writes.
Future<SupabaseClient?> _initSupabase() async {
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) return null;
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      // `publishableKey`, not the deprecated `anonKey`: the project issues an
      // `sb_publishable_...` key, and it is meant to ship in the client. RLS
      // is what protects the data.
      publishableKey: _supabaseAnonKey,
    );
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

class ShelfLifeApp extends StatelessWidget {
  const ShelfLifeApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'ShelfLife',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const _Gate(),
        ),
      );
}

/// Decides the first screen.
///
/// Three states, in order: onboarding not yet seen, seen but no session, and
/// signed in or guest. Reading straight from Hive makes this synchronous, so
/// there is no splash screen — there is nothing to wait for.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.onboardingSeen) return const _Onboarding();
    if (app.userId == null) return const _Welcome();
    return const AppShell();
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding();

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => ValuePropScreen(
        index: _index,
        onSkip: () => AppScope.read(context).markOnboardingSeen(),
        onNext: () {
          if (_index == ValueProp.all.length - 1) {
            AppScope.read(context).markOnboardingSeen();
          } else {
            setState(() => _index++);
          }
        },
      );
}

class _Welcome extends StatefulWidget {
  const _Welcome();

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  bool _busy = false;
  String? _problem;

  Future<void> _google() async {
    final app = AppScope.read(context);
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
    // No navigation on success: the gate watches AppState and swaps the
    // welcome screen for the shell on its own.
  }

  @override
  Widget build(BuildContext context) => WelcomeScreen(
        showGoogle: AppScope.of(context).canSignInWithGoogle,
        googleBusy: _busy,
        problem: _problem,
        onGoogle: _google,
        onCreateAccount: () => _auth(context, CredentialsMode.signUp),
        onSignIn: () => _auth(context, CredentialsMode.signIn),
        onGuest: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (guestContext) => GuestModeScreen(
            onBack: () => Navigator.of(guestContext).pop(),
            onCreateAccount: () {
              Navigator.of(guestContext).pop();
              _auth(context, CredentialsMode.signUp);
            },
            onContinue: () async {
              await AppScope.read(context).continueAsGuest();
              if (guestContext.mounted) Navigator.of(guestContext).pop();
            },
          ),
        )),
      );

  void _auth(BuildContext context, CredentialsMode mode) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AuthPage(mode: mode),
      ));
}
