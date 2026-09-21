import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// A call announcing itself, so the other side rings.
///
/// Membership alone cannot do this. Membership is room *state*, and state
/// changes do not fire push rules — so a learner whose app was closed would
/// never learn they were being called. A timeline event does, which is why the
/// ecosystem rings off one (MSC4075) rather than off state.
///
/// Built to what Element actually ships rather than to the proposal text, where
/// the two differ: the caps below follow matrix-js-sdk and element-web, so a
/// Matrix peer and this client agree about when a call has stopped ringing.
class CallNotification {
  /// How long this rings for. Matches the only shipped sender.
  static const lifetime = Duration(seconds: 30);

  /// Longest a receiver will honour, however long the sender asked for.
  ///
  /// Ninety seconds is what matrix-js-sdk and element-web both enforce. The
  /// proposal suggests two minutes; the implementations agree with each other
  /// instead, and agreeing with the peer matters more than agreeing with the
  /// text.
  static const maxLifetime = Duration(seconds: 90);

  /// How far the sender's clock may differ before it is disbelieved.
  ///
  /// Also from element-web. The proposal says twenty seconds.
  static const maxClockSkew = Duration(seconds: 15);

  /// The call this refers to: the sender's own membership event.
  final String membershipEventId;

  /// The device placing the call.
  ///
  /// The proposal marks this mandatory even though its own example and Element
  /// both omit it. It is carried because it is the hook a ring acknowledgement
  /// needs — a caller with several devices learning which one a callee's phone
  /// is ringing — and because a spec-strict receiver may require it. Receivers
  /// that ignore it are unaffected.
  final String senderDeviceId;
  final bool video;

  const CallNotification({
    required this.membershipEventId,
    required this.senderDeviceId,
    required this.video,
  });

  /// The event content, in the shape MSC4075 specifies.
  ///
  /// The call's own fields sit INSIDE `application`, which is an object rather
  /// than a bare type string — the proposal's own example reads
  /// `"application": {"type": "m.call", "notification_type": ..., "sender_ts":
  /// ..., "lifetime": ..., "m.call.intent": ...}`, with only the text, the
  /// mentions and the relation at the top level. An earlier revision put them
  /// at the top level, and reading this against that revision has been reported
  /// as a spec violation; it is not.
  Map<String, dynamic> toContent(DateTime now) => {
    'application': {
      'type': 'm.call',
      'notification_type': 'ring',
      'sender_ts': now.millisecondsSinceEpoch,
      'lifetime': lifetime.inMilliseconds,
      'm.call.intent': video ? 'video' : 'audio',
      'device_id': senderDeviceId,
    },
    // Fallback text, and the mentions that decide who is notified. The only
    // shipped sender broadcasts to the room rather than naming users, and in a
    // direct message that is the same set.
    'm.text': [
      {'body': 'Incoming call'},
    ],
    'm.mentions': {'user_ids': <String>[], 'room': true},
    'm.relates_to': {'rel_type': 'm.reference', 'event_id': membershipEventId},
  };
}

/// A received call notification, and whether it should ring here.
class IncomingCallNotification {
  final Event event;
  final String myUserId;

  /// Whether this account is already in the call the notification refers to.
  final bool alreadyJoined;

  const IncomingCallNotification({
    required this.event,
    required this.myUserId,
    required this.alreadyJoined,
  });

  Map<String, dynamic>? get _application {
    final application = event.content['application'];
    return application is Map<String, dynamic> ? application : null;
  }

  /// Whether the sender asked for an audible ring rather than a quiet notice.
  bool get isRing => _application?['notification_type'] == 'ring';

  bool get isVideo => videoFromContent(event.content);

  /// Whether a ring asked for video, read straight from event content.
  ///
  /// The push handler has no session and no notification object -- only the
  /// raw event -- and the intent key belongs in one place, so a notification
  /// arriving on a locked phone cannot come to a different conclusion from
  /// the banner.
  static bool videoFromContent(Map<String, Object?> content) {
    final application = content['application'];
    return application is Map && application['m.call.intent'] == 'video';
  }

  /// The device that placed the call, or null if the sender did not say.
  String? get senderDeviceId {
    final id = _application?['device_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// The membership this notification is about, or null if it names none.
  String? get membershipEventId {
    final relation = event.content['m.relates_to'];
    if (relation is! Map) return null;
    if (relation['rel_type'] != 'm.reference') return null;
    final id = relation['event_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// When the sender says they rang.
  ///
  /// Their clock is used unless it disagrees with the server's by more than
  /// [CallNotification.maxClockSkew], in which case the server's is taken — a
  /// device with a badly wrong clock would otherwise make a call look either
  /// long expired or far in the future.
  DateTime get sentAt {
    final claimed = _application?['sender_ts'];
    final serverTs = event.originServerTs;
    if (claimed is! int) return serverTs;
    final sender = DateTime.fromMillisecondsSinceEpoch(claimed);
    final skew = sender.difference(serverTs).abs();
    return skew > CallNotification.maxClockSkew ? serverTs : sender;
  }

  /// When this stops ringing.
  Duration get lifetime {
    final asked = _application?['lifetime'];
    final wanted = asked is int
        ? Duration(milliseconds: asked)
        : CallNotification.lifetime;
    if (wanted.isNegative) return Duration.zero;
    return wanted > CallNotification.maxLifetime
        ? CallNotification.maxLifetime
        : wanted;
  }

  DateTime get expiresAt => sentAt.add(lifetime);

  /// When this ring happened, for putting events in ORDER.
  ///
  /// Not [sentAt], which is the sender's own account of when they rang and is
  /// preferred while it is within the skew allowance. That is the right
  /// reading for a LIFETIME -- how long the caller promised to wait is the
  /// caller's statement -- and the wrong one for sequencing this ring against
  /// anything the server stamped, because the two are different clocks. Every
  /// bug of that shape found so far has been the same mistake: a caller ten
  /// seconds fast made a new ring look older than the call it interrupted,
  /// and a sibling's answer look older than the ring it answered.
  DateTime get orderedAt => event.originServerTs;

  /// Whether this ring has run out.
  ///
  /// Read against THIS device's clock, which is what the proposal prescribes —
  /// and which means a device whose own clock runs fast reads valid rings as
  /// expired and under-rings. Granting a skew allowance here was tried and is
  /// worse: it makes a ring outlive its stated lifetime, and it makes a
  /// notification whose lifetime is zero or negative — an explicit do-not-ring
  /// — ring anyway. Both are behaviours this app deliberately has, and the
  /// clock they would be traded for cannot be told apart from an old event
  /// without a clock we already trust.
  bool hasExpiredBy(DateTime now) => !now.isBefore(expiresAt);

  /// Whether this device should ring.
  ///
  /// Every reason to stay quiet is a real one seen in the wild: a notification
  /// this account sent, one for a call it is already in, one that arrived after
  /// the call was over, and one naming no call at all.
  /// Whether this notification is about a CALL.
  ///
  /// The proposal carries other MatrixRTC applications through the same event —
  /// a whiteboard session announcing itself, say — and any of them may ask to
  /// ring. Without this, one of those would put a call card on screen.
  bool get isCall => _application?['type'] == 'm.call';

  bool shouldRing(DateTime now) =>
      event.type == PangeaEventTypes.callNotification &&
      isCall &&
      event.senderId != myUserId &&
      !alreadyJoined &&
      isRing &&
      membershipEventId != null &&
      !hasExpiredBy(now);
}
