import 'dart:convert';

import 'package:matrix/matrix.dart' show Logs;
import 'package:shared_preferences/shared_preferences.dart';

/// The trace a live call leaves so a reload can offer the way back.
///
/// Written when a call becomes a conversation and REMOVED only by the call's
/// own clean teardown -- so its presence at startup means one thing: this
/// device died mid-call. That makes it the reliable rejoin signal where the
/// room-state membership is not: on a server with working delayed events the
/// server retracts a dead device's membership within seconds of the
/// heartbeat stopping, racing -- and often beating -- the startup scan. The
/// breadcrumb answers to nobody's timer but its own age bound.
class CallBreadcrumb {
  static const _key = 'pangea.call.breadcrumb';

  /// How old a breadcrumb may be and still offer a return. Generous against
  /// the SFU's ~20s room retention plus a slow app start; the tap-time join
  /// is still the truth about whether the call exists.
  static const maxAge = Duration(seconds: 90);

  final String roomId;

  /// The call's standing identity: this device's membership event id, carried
  /// into the rejoined session as its anchor.
  final String membershipEventId;
  final DateTime at;

  /// Whether the call being returned to was a VIDEO call.
  ///
  /// Kept because a rejoin has no other way to know. Returning always as
  /// audio meant a video call came back with the camera off and the other
  /// person watching their picture vanish for good.
  final bool video;

  const CallBreadcrumb({
    required this.roomId,
    required this.membershipEventId,
    required this.at,
    this.video = false,
  });

  static Future<void> drop({
    required String roomId,
    required String membershipEventId,
    bool video = false,
  }) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(
        _key,
        jsonEncode({
          'roomId': roomId,
          'membershipEventId': membershipEventId,
          'video': video,
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e, s) {
      // Losing the breadcrumb costs a rejoin offer after a crash, never the
      // call itself.
      Logs().w('Could not write the call breadcrumb', e, s);
    }
  }

  /// The clean-teardown erase. A breadcrumb that survives is the signal.
  static Future<void> clear() async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.remove(_key);
    } catch (e, s) {
      Logs().w('Could not clear the call breadcrumb', e, s);
    }
  }

  /// The breadcrumb, if one is standing and young enough. An expired one is
  /// cleared on the way out -- it must not resurface on the next start.
  static Future<CallBreadcrumb?> read() async {
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final roomId = json['roomId'];
      final membership = json['membershipEventId'];
      final at = json['at'];
      if (roomId is! String || membership is! String || at is! int) {
        await store.remove(_key);
        return null;
      }
      final crumb = CallBreadcrumb(
        roomId: roomId,
        membershipEventId: membership,
        video: json['video'] == true,
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );
      if (DateTime.now().difference(crumb.at) > maxAge) {
        await store.remove(_key);
        return null;
      }
      return crumb;
    } catch (e, s) {
      Logs().w('Could not read the call breadcrumb', e, s);
      return null;
    }
  }
}
