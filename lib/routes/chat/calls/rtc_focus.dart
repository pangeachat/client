import 'package:matrix/matrix.dart';

/// Where a MatrixRTC call's media is relayed, and how a client authenticates to it.
///
/// The SDK does not discover this. `LiveKitBackend` stores `livekitServiceUrl` and
/// serialises it into the membership event's `foci_active`, but never reads
/// `.well-known` and never calls the service — see
/// `2026-08-17-voice-video-v1-design-spec.md`. Discovery is the app's job, which is
/// what this file is.
class RtcFocus {
  /// Base URL of the MatrixRTC authorization service (lk-jwt-service), e.g.
  /// `http://localhost:7980`. Not the SFU — this is the thing that trades a Matrix
  /// OpenID token for a LiveKit JWT.
  final String serviceUrl;

  const RtcFocus({required this.serviceUrl});

  /// Unstable key under which a homeserver advertises its RTC foci. MSC4143 is still
  /// an open proposal, so this prefix is expected to move; it is isolated here so the
  /// change is one line.
  static const wellKnownKey = 'org.matrix.msc4143.rtc_foci';

  /// Reads the focus a homeserver advertises, if any.
  ///
  /// Returns null rather than throwing when no focus is advertised: a homeserver
  /// without MatrixRTC configured is a normal state, and the caller decides whether
  /// that means "hide the call button" or "fall back to configuration".
  static RtcFocus? fromWellKnown(DiscoveryInformation? wellKnown) {
    final raw = wellKnown?.additionalProperties[wellKnownKey];
    if (raw is! List) return null;

    for (final entry in raw) {
      if (entry is! Map) continue;
      if (entry['type'] != 'livekit') continue;
      final url = entry['livekit_service_url'];
      if (url is String && url.isNotEmpty) return RtcFocus(serviceUrl: url);
    }
    return null;
  }

  /// Builds the backend the SDK publishes into the call membership event.
  ///
  /// `e2eeEnabled: false` is deliberate and load-bearing. The SDK defaults it to true
  /// (asserted in test/pangea/calls/sdk_voip_surface_test.dart), but Pangea rooms are
  /// created unencrypted and MSC4143 states MatrixRTC encryption MUST NOT be used in
  /// unencrypted rooms. We also transcribe the call by design, so encrypting media we
  /// hold the keys to would be theatre. Inheriting the default here would produce a
  /// call that is encrypted-in-name against a plaintext room.
  LiveKitBackend backendForRoom(String roomId) => LiveKitBackend(
    livekitServiceUrl: serviceUrl,
    livekitAlias: roomId,
    e2eeEnabled: false,
  );

  @override
  bool operator ==(Object other) =>
      other is RtcFocus && other.serviceUrl == serviceUrl;

  @override
  int get hashCode => serviceUrl.hashCode;

  @override
  String toString() => 'RtcFocus($serviceUrl)';
}
