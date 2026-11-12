import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';

import 'package:fluffychat/features/join_codes/qr_scanner_modal_stub.dart'
    if (dart.library.io) 'package:fluffychat/features/join_codes/qr_scanner_modal.dart'
    as scanner;

/// What the camera sheet ended with: a read code, or the camera refused.
class QrScanResult {
  final String? code;
  final bool cameraDenied;

  const QrScanResult.scanned(String this.code) : cameraDenied = false;

  const QrScanResult.cameraDenied() : code = null, cameraDenied = true;
}

/// Scanning a course's QR code to join it (joining-courses.instructions.md
/// § Route 2 — Class Code). iOS and Android only.
class QrCodeScan {
  @visibleForTesting
  static bool isWeb = kIsWeb;

  static bool get available =>
      !isWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Opens the camera sheet. Replaced in tests, which have no camera.
  static Future<QrScanResult?> Function(BuildContext context) open =
      scanner.showQrScanner;

  /// The course code a scan carries: a course link on this build's app host
  /// or a bare code. Null for anything else, which is never sent to the
  /// server — a scanned QR code can hold anything, a Wi-Fi password included.
  static String? courseCode(String scanned) {
    final code = SpaceCodeController.codeFromInput(scanned);
    return PRoutes.isJoinCode(code) ? code : null;
  }
}
