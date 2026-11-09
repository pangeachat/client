import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';

/// The `room:` (and `session:`) panel token's structured param.
///
/// Field 0 is the room id (never containing `/`); an optional `.c` field and
/// an optional sub-path follow, `/`-delimited:
/// ```
/// param = <id> [ '.c' ] [ '/' <sub> ]
/// <sub> = 'search'
///       | 'invite' [ '/' <filter> ]
///       | 'details' [ '/' <page> [ '/' <filter> ] ]
///       | 'e' '/' <eventId>          // jump-to-message on the main timeline
/// ```
/// This replaces the loose `?event=`/`?filter=` query params the FluffyChat
/// base carried for jump-to-message and the invite-page contact filter — every
/// panel needs rides in its token, with no second query channel to sweep (see
/// `routing.instructions.md`). [filter] and [eventId] are open-ended content
/// (an eventId carries `$`, `:`, `/`) and are [TokenFields]-encoded so they
/// can't collide with the `/` sub-path separator. The FluffyChat params get no
/// exception: the client is a hard fork, and one consistent grammar outranks
/// staying close to the base.
///
/// `.c` ([fromCourseCard]) marks a session started from an activity the
/// course card opened, so closing it reopens the card (#9632). A room id never
/// ends in `.c`: a home localpart has no dot and a server name ends in a
/// top-level domain of two or more letters, or in a port or an IP address.
class RoomTokenParam extends TokenParam {
  final String id;
  final String? subpage;
  final InvitationFilter? filter;
  final String? eventId;
  final bool fromCourseCard;

  const RoomTokenParam({
    required this.id,
    this.subpage,
    this.filter,
    this.eventId,
    this.fromCourseCard = false,
  });

  static const String _fromCourseCardField = '.c';

  @override
  bool get isPushed => subpage != null;

  /// Popping a sub-page keeps [fromCourseCard]: the session is still the one
  /// the course card opened.
  @override
  RoomTokenParam? get poppedParam =>
      isPushed ? RoomTokenParam(id: id, fromCourseCard: fromCourseCard) : null;

  /// Build a `room:`/`session:` param. At most one of [subpage] / [eventId] is
  /// meaningful at a time — a jump-to-message has no sub-page of its own, so
  /// [eventId] takes precedence when both are passed. [filter] only ever trails
  /// an `invite` sub-page (bare or under `details/`); it is ignored otherwise.
  @override
  String build() {
    final head = fromCourseCard ? '$id$_fromCourseCardField' : id;
    final eventId = this.eventId;
    if (eventId != null && eventId.isNotEmpty) {
      return '$head/e/${TokenFields.encode(eventId)}';
    }

    final subPage = subpage;
    if (subPage == null || subPage.isEmpty) return head;

    // A filter only round-trips under `invite` / `details/invite` (see [parse]);
    // appending it to any other sub-page would build a token parse can't read
    // back. Ignore it elsewhere rather than emit a lossy token.
    final filter = this.filter;
    final allowsFilter = subPage == 'invite' || subPage == 'details/invite';
    final withFilter = allowsFilter && filter != null
        ? '$subPage/${TokenFields.encode(filter.name)}'
        : subPage;

    return '$head/$withFilter';
  }

  /// Parse a `room:`/`session:` param. Unknown/malformed sub-paths degrade to a
  /// bare [subpage] rather than throwing, so a hand-edited or older URL still
  /// opens the room.
  factory RoomTokenParam.parse(String param) {
    final slash = param.indexOf('/');
    final head = slash < 0 ? param : param.substring(0, slash);
    final fromCourseCard = head.endsWith(_fromCourseCardField);
    final id = fromCourseCard
        ? head.substring(0, head.length - _fromCourseCardField.length)
        : head;
    if (slash < 0) {
      return RoomTokenParam(id: id, fromCourseCard: fromCourseCard);
    }
    final sub = param.substring(slash + 1);
    final parts = sub.split('/');

    if (parts.first == 'e' && parts.length > 1) {
      return RoomTokenParam(
        id: id,
        eventId: TokenFields.decode(parts[1]),
        fromCourseCard: fromCourseCard,
      );
    }

    // A trailing filter only ever follows `invite` (bare) or `details/invite`.
    if (parts.first == 'invite' && parts.length > 1) {
      return RoomTokenParam(
        id: id,
        subpage: 'invite',
        filter: InvitationFilter.fromString(TokenFields.decode(parts[1])),
        fromCourseCard: fromCourseCard,
      );
    }
    if (parts.first == 'details' && parts.length > 2 && parts[1] == 'invite') {
      return RoomTokenParam(
        id: id,
        subpage: 'details/invite',
        filter: InvitationFilter.fromString(TokenFields.decode(parts[2])),
        fromCourseCard: fromCourseCard,
      );
    }

    return RoomTokenParam(id: id, subpage: sub, fromCourseCard: fromCourseCard);
  }

  @override
  bool operator ==(Object other) =>
      other is RoomTokenParam &&
      other.id == id &&
      other.subpage == subpage &&
      other.filter == filter &&
      other.eventId == eventId &&
      other.fromCourseCard == fromCourseCard;

  @override
  int get hashCode => Object.hash(id, subpage, filter, eventId, fromCourseCard);
}
