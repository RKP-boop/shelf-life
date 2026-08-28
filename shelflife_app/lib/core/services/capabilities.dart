/// Native capabilities behind interfaces.
///
/// Each has a real implementation (Android plugins) and a fake. This is what
/// lets all 52 screens compile and run on web and in tests, where no camera,
/// no ML Kit and no notification channel exist.
///
/// It also means the OCR pipeline is testable against a fixture image rather
/// than requiring someone to hold a receipt up to a camera — which is both
/// deterministic and a better test.
library;

import 'dart:async';
import 'dart:typed_data';

// ------------------------------------------------------------------- OCR

abstract interface class OcrService {
  /// Recognised text, or null when nothing could be read.
  ///
  /// Returning null rather than throwing is deliberate: an unreadable receipt
  /// is an expected outcome with its own designed screen (16, "We couldn't
  /// read the receipt"), not an error condition.
  Future<String?> recognise(Uint8List imageBytes);

  Future<void> dispose();
}

/// Returns canned text. The default is a real DMart receipt, so the review
/// screen has plausible content on web and in tests.
class FakeOcrService implements OcrService {
  FakeOcrService({this.text = _sample, this.shouldFail = false});

  final String? text;

  /// Lets the OCR-failure screen be exercised without a broken image.
  final bool shouldFail;

  @override
  Future<String?> recognise(Uint8List imageBytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return shouldFail ? null : text;
  }

  @override
  Future<void> dispose() async {}

  static const _sample = '''
DMART
AVENUE SUPERMARTS LTD
GSTIN: 27AACCA8432H1ZM
--------------------------------
AASHIRVAAD ATTA 5KG        1  325.00
AMUL TAAZA TONED MILK 1L   2  132.00
FRESH PALAK 250G           1   28.00
TOMATO LOCAL 1KG           1   42.00
ONION 2KG                  1   68.00
AMUL PANEER 200G           1   95.00
DHANIA 100G                1   15.00
--------------------------------
GRAND TOTAL               705.00
THANK YOU FOR SHOPPING
''';
}

// --------------------------------------------------------------- barcode

class BarcodeResult {
  const BarcodeResult({required this.value, required this.format});
  final String value;
  final String format;
}

abstract interface class BarcodeScannerService {
  /// Emits each successful decode. A stream rather than a future because the
  /// viewfinder stays open and may read several packs in a row.
  Stream<BarcodeResult> scan();

  Future<void> stop();
}

class FakeBarcodeScannerService implements BarcodeScannerService {
  FakeBarcodeScannerService({this.value = '8901030865278'});

  /// Defaults to Amul Taaza — a barcode that IS in the seeded cache, so the
  /// found path is the default and the not-found path is opt-in.
  final String value;

  @override
  Stream<BarcodeResult> scan() async* {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    yield BarcodeResult(value: value, format: 'EAN_13');
  }

  @override
  Future<void> stop() async {}
}

// ----------------------------------------------------------------- camera

abstract interface class CameraService {
  Future<bool> requestPermission();
  Future<bool> hasPermission();

  /// JPEG bytes, or null if the user cancelled.
  Future<Uint8List?> capture();
}

class FakeCameraService implements CameraService {
  FakeCameraService({this.granted = true});

  bool granted;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<Uint8List?> capture() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // A single-pixel PNG. The fake OCR ignores the bytes entirely; this exists
    // so the type contract is honest rather than returning an empty list.
    return Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ]);
  }
}

// ----------------------------------------------------------- notifications

class PendingReminder {
  const PendingReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
}

abstract interface class NotificationScheduler {
  Future<bool> requestPermission();
  Future<void> schedule(PendingReminder reminder);
  Future<void> cancel(int id);
  Future<List<PendingReminder>> pending();
}

/// Records what was scheduled, so tests can assert on the reminder ladder
/// without a notification channel.
class FakeNotificationScheduler implements NotificationScheduler {
  FakeNotificationScheduler({this.granted = true});

  bool granted;
  final Map<int, PendingReminder> scheduled = {};

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> schedule(PendingReminder reminder) async {
    if (!granted) return;
    scheduled[reminder.id] = reminder;
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<List<PendingReminder>> pending() async => scheduled.values.toList();
}

// ------------------------------------------------------------- connectivity

abstract interface class ConnectivityService {
  Future<bool> get isOnline;
  Stream<bool> get onChanged;
}

class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({bool online = true}) : _online = online;

  // Not an initializing formal: the public setter below has to notify the
  // stream, so the field and the parameter cannot be the same thing.
  // ignore: prefer_initializing_formals
  bool _online;

  /// Flip this in a test to exercise the offline banner and the queue drain.
  set online(bool v) {
    _online = v;
    _controller.add(v);
  }

  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onChanged => _controller.stream;

  void dispose() => _controller.close();
}

/// Registry, so screens depend on the interfaces rather than on plugins.
/// Android registers the real implementations at startup; web and tests get
/// the fakes.
class Capabilities {
  Capabilities({
    required this.ocr,
    required this.barcode,
    required this.camera,
    required this.notifications,
    required this.connectivity,
  });

  factory Capabilities.fakes() => Capabilities(
        ocr: FakeOcrService(),
        barcode: FakeBarcodeScannerService(),
        camera: FakeCameraService(),
        notifications: FakeNotificationScheduler(),
        connectivity: FakeConnectivityService(),
      );

  final OcrService ocr;
  final BarcodeScannerService barcode;
  final CameraService camera;
  final NotificationScheduler notifications;
  final ConnectivityService connectivity;
}
