import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import 'package:fluffychat/features/join_codes/qr_code_scan.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';

/// Opens the camera and resolves with the first code it reads, the camera
/// being refused, or null when the learner closes the sheet. Phones only: the
/// web build never imports this file (see [QrCodeScan.open]).
Future<QrScanResult?> showQrScanner(BuildContext context) =>
    showAdaptiveBottomSheet<QrScanResult>(
      context: context,
      builder: (_) => const QrScannerModal(),
    );

class QrScannerModal extends StatefulWidget {
  const QrScannerModal({super.key});

  @override
  QrScannerModalState createState() => QrScannerModalState();
}

class QrScannerModalState extends State<QrScannerModal> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  StreamSubscription<Barcode>? _scans;
  bool _done = false;

  @override
  void dispose() {
    _scans?.cancel();
    super.dispose();
  }

  /// Closes the sheet once, whichever of a read or a refusal comes first.
  void _finish(QrScanResult result) {
    if (_done || !mounted) return;
    _done = true;
    _scans?.cancel();
    Navigator.of(context).pop(result);
  }

  void _onQRViewCreated(QRViewController controller) {
    // The Android camera starts paused
    // (https://github.com/juliuscanute/qr_code_scanner/issues/538#issuecomment-1133883828).
    if (defaultTargetPlatform == TargetPlatform.android) {
      controller.pauseCamera();
    }
    controller.resumeCamera();
    _scans = controller.scannedDataStream.listen((scan) {
      final code = scan.code;
      if (code != null && code.isNotEmpty) _finish(QrScanResult.scanned(code));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_outlined),
          onPressed: Navigator.of(context).pop,
          tooltip: L10n.of(context).close,
        ),
        title: Text(L10n.of(context).scanQrCode),
      ),
      body: QRView(
        key: _qrKey,
        onQRViewCreated: _onQRViewCreated,
        onPermissionSet: (_, granted) {
          if (!granted) _finish(const QrScanResult.cameraDenied());
        },
        overlay: QrScannerOverlayShape(
          borderColor: Theme.of(context).colorScheme.primary,
          borderRadius: 10,
          borderLength: 30,
          borderWidth: 8,
        ),
      ),
    );
  }
}
