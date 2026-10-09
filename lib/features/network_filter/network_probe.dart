import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

/// What came back when the app asked a host for a page.
enum NetworkProbeResult {
  /// The host answered. Any status counts: an error from our own server is
  /// an outage, not a block.
  answered,

  /// Another site answered in the host's place: a redirect off the host, the
  /// shape a filter's block page takes. Only the native apps can see this; a
  /// browser hides who answered.
  answeredElsewhere,

  /// The connection was refused, reset, or failed its TLS handshake before
  /// any answer.
  refused,

  /// No answer within [NetworkProbe.timeout].
  slow;

  bool get blocked => this == refused || this == answeredElsewhere;
}

/// One request to one host, classified by who answered. See
/// filtered-network.instructions.md, "Detecting a block".
abstract final class NetworkProbe {
  static const Duration timeout = Duration(seconds: 4);

  /// The addresses Android, ChromeOS and Apple devices ask to decide whether
  /// they are online. Filters let them through, because blocking them makes
  /// every device on the network report "no internet".
  static final List<Uri> neutralUrls = [
    Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
    Uri.parse('https://captive.apple.com/hotspot-detect.html'),
  ];

  static Future<NetworkProbeResult> probe(Uri url) =>
      kIsWeb ? _probeFromBrowser(url) : probeWithClient(url, http.Client());

  /// A `no-cors` fetch resolves for any answer, our own error statuses
  /// included, and rejects only when no answer came at all.
  static Future<NetworkProbeResult> _probeFromBrowser(Uri url) async {
    try {
      await html.window
          .fetch(url.toString(), {
            'mode': 'no-cors',
            'cache': 'no-store',
            'redirect': 'follow',
          })
          .timeout(timeout);
      return NetworkProbeResult.answered;
    } on TimeoutException {
      return NetworkProbeResult.slow;
    } catch (_) {
      // silent-ok: a rejected fetch is the measurement — the refusal itself.
      return NetworkProbeResult.refused;
    }
  }

  @visibleForTesting
  static Future<NetworkProbeResult> probeWithClient(
    Uri url,
    http.Client client,
  ) async {
    final request = http.Request('HEAD', url)..followRedirects = false;
    try {
      final response = await client.send(request).timeout(timeout);
      return _redirectsAway(url, response)
          ? NetworkProbeResult.answeredElsewhere
          : NetworkProbeResult.answered;
    } on TimeoutException {
      return NetworkProbeResult.slow;
    } catch (_) {
      // silent-ok: a failed request is the measurement. package:http wraps a
      // socket failure in a ClientException but passes a TLS failure (a filter
      // presenting its own certificate) through as a raw HandshakeException,
      // so both land here as a refusal.
      return NetworkProbeResult.refused;
    } finally {
      client.close();
    }
  }

  static bool _redirectsAway(Uri url, http.StreamedResponse response) {
    if (response.statusCode < 300 || response.statusCode >= 400) return false;
    final location = response.headers['location'];
    if (location == null) return false;
    return url.resolve(location).host != url.host;
  }
}
