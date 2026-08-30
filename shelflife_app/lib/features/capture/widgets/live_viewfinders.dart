// The live camera previews.
//
// The capture screens take a `viewfinder` widget rather than opening a camera
// themselves, which is what lets all 52 screens render in a golden test on a
// machine with no camera. These are the real implementations that fill that
// slot on a device — and the thing that was missing: the screens were built
// with the seam and nothing was ever plugged into it, so both the receipt and
// barcode screens showed a flat dark rectangle and mobile_scanner never
// detected anything, because its preview widget has to be in the tree for the
// camera to run at all.
//
// Everything plugin-shaped is confined to this file and
// core/services/platform_capabilities.dart. The screens stay plugin-free.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/platform_capabilities.dart';
import '../../../core/theme/tokens.g.dart';

/// Live preview for the receipt camera (screen 14).
///
/// Owns nothing: the [DeviceCameraService] holds the controller so the shutter
/// and the preview act on the same camera.
class CameraViewfinder extends StatefulWidget {
  const CameraViewfinder({super.key, required this.service, this.onDenied});

  final DeviceCameraService service;

  /// Called when the user refuses the camera. The flow offers adding by hand
  /// instead, which is a complete path — a refused camera is not a dead end.
  final VoidCallback? onDenied;

  @override
  State<CameraViewfinder> createState() => _CameraViewfinderState();
}

enum _Preview { starting, ready, denied }

class _CameraViewfinderState extends State<CameraViewfinder>
    with WidgetsBindingObserver {
  _Preview _state = _Preview.starting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The service owns the controller and the flow may still need it for the
    // shutter, so this disposes nothing.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android reclaims the camera when the app goes to the background. Without
    // this the preview comes back frozen.
    if (state == AppLifecycleState.resumed && _state == _Preview.ready) {
      _start();
    }
  }

  Future<void> _start() async {
    final ok = await widget.service.start();
    if (!mounted) return;
    setState(() => _state = ok ? _Preview.ready : _Preview.denied);
    if (!ok) widget.onDenied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.service.controller;

    return switch (_state) {
      _Preview.ready when controller != null && controller.value.isInitialized =>
        _FilledPreview(controller: controller),
      _Preview.denied => _PermissionNotice(onRetry: _start),
      _ => const _Starting(),
    };
  }
}

/// Live preview for the barcode scanner (screen 20).
///
/// `MobileScanner` starts and stops the camera itself, which is why the
/// service does not: two things calling start() on one controller is how you
/// get a preview that is black on the second visit.
class BarcodeViewfinder extends StatelessWidget {
  const BarcodeViewfinder({super.key, required this.service});

  final MobileScannerBarcodeService service;

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: service.controller,
        fit: BoxFit.cover,
        // Detections are consumed from the controller's stream by the flow, so
        // this widget only draws. Handing it an onDetect as well would deliver
        // every scan twice.
        placeholderBuilder: (_) => const _Starting(),
        errorBuilder: (_, error) => _PermissionNotice(
          onRetry: null,
          message: switch (error.errorCode) {
            MobileScannerErrorCode.permissionDenied =>
              'ShelfLife needs the camera to read a barcode. You can allow it '
                  'in Settings, or add the item by hand.',
            MobileScannerErrorCode.unsupported =>
              'This phone cannot scan barcodes. Adding by hand works just as '
                  'well.',
            _ => 'The camera would not start. Adding by hand works just as '
                'well.',
          },
        ),
      );
}

/// Fills the screen with the preview, cropping rather than letterboxing.
///
/// A camera preview has its own aspect ratio and will not match the phone.
/// Left alone it letterboxes, which inside a dark full-screen camera reads as
/// the app being broken. This scales it up until it covers and clips the
/// overflow, the way every camera app behaves.
class _FilledPreview extends StatelessWidget {
  const _FilledPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    // previewSize is reported in the sensor's own landscape orientation, so
    // the sides are swapped for a portrait screen.
    final preview = controller.value.previewSize;
    final width = preview?.height ?? 1;
    final height = preview?.width ?? 1;

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: width,
            height: height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: T.overlayScrim,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: T.textOnAccent),
          ),
        ),
      );
}

/// Shown instead of a black rectangle when the camera is unavailable.
///
/// Says what is missing, what it is for, and that there is another way in —
/// a viewfinder that is simply black tells the user the app is broken.
class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.onRetry, this.message});

  final VoidCallback? onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: T.overlayScrim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined,
                    size: 54, color: T.textOnAccent),
                const SizedBox(height: 18),
                Text(
                  message ??
                      'ShelfLife needs the camera to read your receipt. You '
                          'can allow it, or add things by hand instead.',
                  textAlign: TextAlign.center,
                  style: T.bodyRegular14.copyWith(color: T.textOnAccent),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      backgroundColor: T.textOnAccent,
                      foregroundColor: T.textPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: Text('Allow the camera', style: T.cardSemiBold15),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
