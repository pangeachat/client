import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';

/// The `activity:` panel token's structured param.
///
/// Field 0 is the activity id; optional session-binding fields follow, each
/// tagged by its first character: `r<roomid>` (the learner's bound session
/// room, bare localpart), `l` (launch the session on arrival), `a<index>`
/// (autoplay the plan's media at that carousel index). These fields replaced
/// the loose `?roomid=` / `?launch=` / `?autoplay=` query params — everything
/// a panel needs rides in its token (routing.instructions.md); the loose
/// spellings survive as inbound shapes that `LegacyRedirects` folds in here.
abstract class ActivityToken {
  static String build(
    String activityId, {
    String? roomId,
    bool launch = false,
    int? autoplay,
  }) => TokenFields.join([
    TokenFields.encode(activityId),
    if (roomId != null) 'r${TokenFields.encode(shortRoomId(roomId))}',
    if (launch) 'l',
    if (autoplay != null) 'a$autoplay',
  ]);

  /// Parse an `activity:` token param. Unknown fields are ignored so a newer
  /// URL degrades rather than failing on an older client.
  static ({String id, String? roomId, bool launch, int? autoplay}) parse(
    String param,
  ) {
    final fields = TokenFields.split(param);
    String? roomId;
    var launch = false;
    int? autoplay;
    for (final field in fields.skip(1)) {
      if (field == 'l') {
        launch = true;
      } else if (field.length > 1 && field.startsWith('r')) {
        roomId = fullRoomId(TokenFields.decode(field.substring(1)));
      } else if (field.length > 1 && field.startsWith('a')) {
        autoplay = int.tryParse(field.substring(1));
      }
    }
    return (
      id: TokenFields.decode(fields.first),
      roomId: roomId,
      launch: launch,
      autoplay: autoplay,
    );
  }
}
