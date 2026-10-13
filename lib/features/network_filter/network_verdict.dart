import 'package:fluffychat/features/network_filter/network_probe.dart';

/// What a check concludes about one host category. See
/// filtered-network.instructions.md, "Detecting a block".
enum NetworkVerdict {
  /// The host answered, slowly or with an error from our own server. Either
  /// way the network let the request through.
  reachable,

  /// Neither the host nor the neutral addresses answered.
  offline,

  /// The neutral addresses answered and the host did not.
  filtered;

  static NetworkVerdict of({
    required NetworkProbeResult needed,
    required bool neutralAnswered,
  }) {
    if (!needed.blocked) return reachable;
    return neutralAnswered ? filtered : offline;
  }
}
