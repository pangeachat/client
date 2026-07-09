import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

/// The `room:` (and `session:`) panel token's structured param.
///
/// Field 0 is the room id (never containing `/`); an optional sub-path
/// follows, `/`-delimited:
/// ```
/// param = <id> [ '/' <sub> ]
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
/// can't collide with the `/` sub-path separator.
class RoomTokenParam extends TokenParam {
  final String id;
  final String? subpage;
  final String? filter;
  final String? eventId;

  const RoomTokenParam({
    required this.id,
    this.subpage,
    this.filter,
    this.eventId,
  });

  @override
  bool get isPushed => subpage != null;

  @override
  RoomTokenParam? get poppedParam => isPushed ? RoomTokenParam(id: id) : null;

  RoomSubpageTokenParam? toSubpageToken() {
    final subpage = this.subpage;
    return subpage != null
        ? RoomSubpageTokenParam(subpage: subpage, filter: filter)
        : null;
  }

  /// Build a `room:`/`session:` param. At most one of [subpage] / [eventId] is
  /// meaningful at a time — a jump-to-message has no sub-page of its own, so
  /// [eventId] takes precedence when both are passed. [filter] only ever trails
  /// an `invite` sub-page (bare or under `details/`); it is ignored otherwise.
  @override
  String build() {
    final eventId = this.eventId;
    if (eventId != null && eventId.isNotEmpty) {
      return '$id/e/${TokenFields.encode(eventId)}';
    }

    final subPage = subpage;
    if (subPage == null || subPage.isEmpty) return id;

    // A filter only round-trips under `invite` / `details/invite` (see [parse]);
    // appending it to any other sub-page would build a token parse can't read
    // back. Ignore it elsewhere rather than emit a lossy token.
    final filter = this.filter;
    final allowsFilter = subPage == 'invite' || subPage == 'details/invite';
    final withFilter = allowsFilter && filter != null && filter.isNotEmpty
        ? '$subPage/${TokenFields.encode(filter)}'
        : subPage;

    return '$id/$withFilter';
  }

  /// Parse a `room:`/`session:` param. Unknown/malformed sub-paths degrade to a
  /// bare [subpage] rather than throwing, so a hand-edited or older URL still
  /// opens the room.
  factory RoomTokenParam.parse(String param) {
    final slash = param.indexOf('/');
    if (slash < 0) {
      return RoomTokenParam(
        id: param,
        subpage: null,
        filter: null,
        eventId: null,
      );
    }
    final id = param.substring(0, slash);
    final sub = param.substring(slash + 1);
    final parts = sub.split('/');

    if (parts.first == 'e' && parts.length > 1) {
      return RoomTokenParam(
        id: id,
        subpage: null,
        filter: null,
        eventId: TokenFields.decode(parts[1]),
      );
    }

    // A trailing filter only ever follows `invite` (bare) or `details/invite`.
    if (parts.first == 'invite' && parts.length > 1) {
      return RoomTokenParam(
        id: id,
        subpage: 'invite',
        filter: TokenFields.decode(parts[1]),
        eventId: null,
      );
    }
    if (parts.first == 'details' && parts.length > 2 && parts[1] == 'invite') {
      return RoomTokenParam(
        id: id,
        subpage: 'details/invite',
        filter: TokenFields.decode(parts[2]),
        eventId: null,
      );
    }

    return RoomTokenParam(id: id, subpage: sub, filter: null, eventId: null);
  }

  @override
  bool operator ==(Object other) =>
      other is RoomTokenParam &&
      other.id == id &&
      other.subpage == subpage &&
      other.filter == filter &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(id, subpage, filter, eventId);
}
