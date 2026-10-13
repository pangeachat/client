import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

/// The `activity:` panel token's structured param.
///
/// Field 0 is the activity id; optional session-binding fields follow, each
/// tagged by its first character: `r<roomid>` (the learner's bound session
/// room, bare localpart), `l` (launch the session on arrival), `a<index>`
/// (autoplay the plan's media at that carousel index), `p` (opened from the
/// course card's full course plan, so the back arrow returns there — #9367).
/// These fields replaced
/// the loose `?roomid=` / `?launch=` / `?autoplay=` query params — everything
/// a panel needs rides in its token (routing.instructions.md); the loose
/// spellings survive as inbound shapes that `LegacyRedirects` folds in here.
class ActivityTokenParam extends TokenParam {
  final String activityId;
  final String? roomId;
  final bool launch;
  final int? autoplay;
  final bool fromCoursePlan;

  const ActivityTokenParam({
    required this.activityId,
    this.roomId,
    this.launch = false,
    this.autoplay,
    this.fromCoursePlan = false,
  });

  @override
  String build() => TokenFields.join([
    TokenFields.encode(activityId),
    if (roomId != null) 'r${TokenFields.encode(shortRoomId(roomId!))}',
    if (launch) 'l',
    if (autoplay != null) 'a$autoplay',
    if (fromCoursePlan) 'p',
  ]);

  /// Parse an `activity:` token param. Unknown fields are ignored so a newer
  /// URL degrades rather than failing on an older client.
  factory ActivityTokenParam.parse(String param) {
    final fields = TokenFields.split(param);
    String? roomId;
    var launch = false;
    int? autoplay;
    var fromCoursePlan = false;
    for (final field in fields.skip(1)) {
      if (field == 'l') {
        launch = true;
      } else if (field == 'p') {
        fromCoursePlan = true;
      } else if (field.length > 1 && field.startsWith('r')) {
        roomId = fullRoomId(TokenFields.decode(field.substring(1)));
      } else if (field.length > 1 && field.startsWith('a')) {
        autoplay = int.tryParse(field.substring(1));
      }
    }
    return ActivityTokenParam(
      activityId: TokenFields.decode(fields.first),
      roomId: roomId,
      launch: launch,
      autoplay: autoplay,
      fromCoursePlan: fromCoursePlan,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActivityTokenParam &&
      other.activityId == activityId &&
      other.roomId == roomId &&
      other.launch == launch &&
      other.autoplay == autoplay &&
      other.fromCoursePlan == fromCoursePlan;

  @override
  int get hashCode =>
      Object.hash(activityId, roomId, launch, autoplay, fromCoursePlan);
}
