import 'package:fluffychat/l10n/l10n.dart';

/// A compact "how long": seconds under a minute, then minutes, hours, days
/// (#9333 prototype — the join list's last-active label and the waiting-room
/// timer).
class ElapsedTimeFormat {
  static String compact(Duration elapsed, L10n l10n) {
    if (elapsed.isNegative) elapsed = Duration.zero;
    if (elapsed.inMinutes < 1) return l10n.elapsedSeconds(elapsed.inSeconds);
    if (elapsed.inHours < 1) return l10n.elapsedMinutes(elapsed.inMinutes);
    if (elapsed.inDays < 1) return l10n.elapsedHours(elapsed.inHours);
    return l10n.elapsedDays(elapsed.inDays);
  }
}
