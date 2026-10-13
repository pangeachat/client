import 'package:connectivity_plus/connectivity_plus.dart';

/// The kind of connection the device is on, as a Sentry tag and in a help
/// request.
enum NetworkType {
  wifi,
  mobileData,
  wired,
  unknown;

  /// The first connection kind the platform reports that we name. Most
  /// browsers report nothing usable, so the web app is mostly [unknown].
  static NetworkType of(List<ConnectivityResult> results) {
    for (final result in results) {
      switch (result) {
        case ConnectivityResult.wifi:
          return wifi;
        case ConnectivityResult.mobile:
          return mobileData;
        case ConnectivityResult.ethernet:
          return wired;
        default:
          continue;
      }
    }
    return unknown;
  }

  static Future<NetworkType> current() async {
    try {
      return of(await Connectivity().checkConnectivity());
    } catch (_) {
      // silent-ok: the type is context on a report, and a report without it
      // is still worth sending.
      return unknown;
    }
  }
}
