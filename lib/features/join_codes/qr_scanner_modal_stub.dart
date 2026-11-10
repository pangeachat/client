import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/join_codes/qr_code_scan.dart';

/// The web build's stand-in for `qr_scanner_modal.dart`, which needs a phone
/// camera plugin the web build does not set up. Never called:
/// [QrCodeScan.available] is false on web.
Future<QrScanResult?> showQrScanner(BuildContext context) =>
    throw UnsupportedError('QR scanning is phone-only');
