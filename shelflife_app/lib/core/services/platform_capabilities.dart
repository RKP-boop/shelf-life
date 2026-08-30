// Real implementations of the capability interfaces.
//
// Everything plugin-shaped lives here and nowhere else. The screens and flows
// depend only on the interfaces in capabilities.dart, which is what lets all
// 52 screens render in a golden test on a machine with no camera, no ML Kit
// and no notification channel.
//
// Each implementation degrades rather than throws. A phone that refuses camera
// permission, or an ML Kit model that will not load, produces the designed
// "we could not read that one" screen — not a crash.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'capabilities.dart';

/// Real capabilities on Android and iOS; fakes everywhere else.
///
/// Web and desktop get fakes rather than a compile error: the same code runs
/// in `flutter test` and in the golden harness, and a plugin-shaped import
/// that only works on a phone would make the whole screen library untestable.
Future<Capabilities> platformCapabilities() async {
  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (!mobile) return Capabilities.fakes();

  final notifications = AndroidNotificationScheduler();
  await notifications.init();

  final google = NativeGoogleAuthService();
  await google.init();

  return Capabilities(
    ocr: MlKitOcrService(),
    barcode: MobileScannerBarcodeService(),
    camera: DeviceCameraService(),
    notifications: notifications,
    connectivity: PlatformConnectivityService(),
    googleAuth: google,
  );
}

// ------------------------------------------------------------------- OCR

class MlKitOcrService implements OcrService {
  TextRecognizer? _recognizer;

  @override
  Future<String?> recognise(Uint8List imageBytes) async {
    // ML Kit reads from a file path, so the captured bytes have to land on
    // disk first. Temp dir, and cleaned up immediately — a folder of the
    // user's receipts accumulating on the device is not something the app
    // should do quietly.
    File? scratch;
    try {
      final dir = await getTemporaryDirectory();
      scratch = File(
          '${dir.path}/receipt_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await scratch.writeAsBytes(imageBytes, flush: true);

      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result =
          await _recognizer!.processImage(InputImage.fromFilePath(scratch.path));

      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      // An unreadable receipt is an expected outcome with its own screen, not
      // an error condition. Returning null routes to screen 19.
      return null;
    } finally {
      if (scratch != null && scratch.existsSync()) {
        try {
          await scratch.delete();
        } catch (_) {
          // Best effort. A leftover temp file is not worth failing a scan for.
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

// --------------------------------------------------------------- barcode

class MobileScannerBarcodeService implements BarcodeScannerService {
  MobileScannerController? _controller;

  /// The controller the viewfinder widget renders. Created lazily so the
  /// camera is not opened until a scan actually starts.
  MobileScannerController get controller => _controller ??=
      MobileScannerController(
        formats: const [
          // Retail barcodes only. Including QR would let the scanner lock onto
          // a random code on the packaging instead of the product barcode.
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
        ],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );

  /// Detections only. Starting and stopping the camera belongs to the
  /// `MobileScanner` widget in the tree — it does that itself, and a second
  /// caller invoking start() on the same controller leaves the preview black
  /// the next time the screen is opened.
  @override
  Stream<BarcodeResult> scan() async* {
    await for (final capture in controller.barcodes) {
      for (final code in capture.barcodes) {
        final value = code.rawValue;
        if (value == null || value.isEmpty) continue;
        yield BarcodeResult(value: value, format: code.format.name);
      }
    }
  }

  Future<void> toggleTorch() async {
    try {
      await _controller?.toggleTorch();
    } catch (_) {
      // Not every device has a torch.
    }
  }

  @override
  Future<void> stop() async {
    await _controller?.stop();
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}

// ---------------------------------------------------------------- camera

class DeviceCameraService implements CameraService {
  CameraController? _controller;

  /// The live controller, for the viewfinder widget. Null until [start].
  CameraController? get controller => _controller;

  @override
  Future<bool> hasPermission() async =>
      (await Permission.camera.status).isGranted;

  @override
  Future<bool> requestPermission() async =>
      (await Permission.camera.request()).isGranted;

  /// Opens the back camera at a resolution high enough for OCR.
  ///
  /// `veryHigh` rather than `max`: receipt text needs resolution, but `max` on
  /// a modern phone produces a frame large enough to be slow to encode and to
  /// push some devices into memory pressure, for no gain in recognition.
  Future<bool> start() async {
    if (_controller != null) return true;
    if (!await requestPermission()) return false;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      _controller = controller;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> capture() async {
    if (!await start()) return null;
    try {
      final shot = await _controller!.takePicture();
      return await shot.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> setTorch(bool on) async {
    try {
      await _controller?.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      // Not every device has a torch. Silently doing nothing is correct.
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}

// ---------------------------------------------------------- notifications

class AndroidNotificationScheduler implements NotificationScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'shelflife_reminders';

  Future<void> init() async {
    if (_ready) return;
    tz.initializeTimeZones();
    // The device's own zone, so "9am" means 9am where the user is rather than
    // 9am UTC. Falling back to UTC keeps scheduling working rather than
    // throwing on a device with an unexpected zone name.
    try {
      tz.setLocalLocation(tz.getLocation(await _timeZoneName()));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  /// The IANA zone name. `DateTime.now().timeZoneName` gives an abbreviation on
  /// some platforms, so the offset is used to pick a zone when it does.
  Future<String> _timeZoneName() async {
    final name = DateTime.now().timeZoneName;
    if (name.contains('/')) return name;
    // India is the target market and IST is unambiguous at +5:30.
    final offset = DateTime.now().timeZoneOffset;
    if (offset == const Duration(hours: 5, minutes: 30)) return 'Asia/Kolkata';
    return 'UTC';
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      // Exact alarms are a separate Android 13+ grant. Without it the schedule
      // still works, just inexactly — which is fine for a 9am reminder, so it
      // is requested but not required.
      await android?.requestExactAlarmsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  @override
  Future<void> schedule(PendingReminder reminder) async {
    await init();
    final when = tz.TZDateTime.from(reminder.when, tz.local);
    // Scheduling into the past either fires immediately or is dropped, and
    // both are wrong. The ladder already filters these; this is the backstop.
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    try {
      await _plugin.zonedSchedule(
        reminder.id,
        reminder.title,
        reminder.body,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Food reminders',
            channelDescription:
                'Nudges before something in your kitchen needs using.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: reminder.payload,
      );
    } catch (_) {
      // A refused exact-alarm permission or a full schedule must not take the
      // add-item flow down with it.
    }
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  @override
  Future<List<PendingReminder>> pending() async {
    await init();
    final requests = await _plugin.pendingNotificationRequests();
    return [
      for (final r in requests)
        PendingReminder(
          id: r.id,
          title: r.title ?? '',
          body: r.body ?? '',
          // The platform does not hand back the fire time, and the ledger in
          // Hive is the authority on that anyway.
          when: DateTime.now(),
          payload: r.payload,
        ),
    ];
  }
}

// ----------------------------------------------------------- connectivity

class PlatformConnectivityService implements ConnectivityService {
  final _connectivity = Connectivity();

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> get isOnline async {
    try {
      return _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      // Assume online when the platform will not say. A false "offline" hides
      // the sync indicator for no reason; a false "online" costs one failed
      // request that the queue retries anyway.
      return true;
    }
  }

  @override
  Stream<bool> get onChanged =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();
}

// ----------------------------------------------------------- google auth

/// Native Google sign-in, exchanged for a Supabase session.
///
/// Native rather than the browser OAuth flow: on Android this uses Credential
/// Manager, so the user picks an account already on the phone instead of
/// being bounced to a browser and back through a deep link. Fewer moving
/// parts and no custom URL scheme to get wrong.
///
/// The Google-issued ID token is what Supabase verifies server-side, so
/// nothing this class returns has to be trusted by the app.
class NativeGoogleAuthService implements GoogleAuthService {
  /// The **Web** OAuth client id from Google Cloud, not the Android one.
  ///
  /// This is the counterintuitive part: Android passes the *web* client id as
  /// `serverClientId`, because that is the audience Supabase validates the
  /// token against. The Android client id still has to exist in Google Cloud —
  /// registered against the app's package name and signing SHA-1 — but it is
  /// never named in code.
  static const _webClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  bool _ready = false;

  /// False when the build carries no client id, which is the default. The
  /// button is then hidden rather than shown and failing on tap.
  @override
  bool get isAvailable => _ready && _webClientId.isNotEmpty;

  Future<void> init() async {
    if (_webClientId.isEmpty) return;
    try {
      await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
      _ready = GoogleSignIn.instance.supportsAuthenticate();
    } catch (_) {
      // A missing Play Services, a bad client id, or an unsupported platform.
      // All of them mean the same thing to the user: this route is not
      // available, so do not offer it.
      _ready = false;
    }
  }

  @override
  Future<GoogleAuthResult> signIn() async {
    if (!isAvailable) {
      return const GoogleAuthResult.failed(GoogleAuthOutcome.notConfigured);
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return const GoogleAuthResult.failed(GoogleAuthOutcome.unavailable);
      }
      return GoogleAuthResult.success(GoogleCredential(
        idToken: idToken,
        email: account.email,
        displayName: account.displayName,
      ));
    } on GoogleSignInException catch (e) {
      // Backing out of the account picker is not a failure and must not
      // produce a message.
      return GoogleAuthResult.failed(
        switch (e.code) {
          GoogleSignInExceptionCode.canceled => GoogleAuthOutcome.cancelled,
          GoogleSignInExceptionCode.uiUnavailable =>
            GoogleAuthOutcome.unavailable,
          _ => GoogleAuthOutcome.refused,
        },
      );
    } catch (_) {
      return const GoogleAuthResult.failed(GoogleAuthOutcome.unavailable);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signing out of the app must not fail because Google would not.
    }
  }
}
