import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/stream_extension.dart';

/// Which course the narrow rail's course-shortcut slot shows, and when that
/// answer changes. See routing.instructions.md → Single-column bottom nav.
///
/// The slot is `+` when no course is joined, and otherwise the
/// **most-recently-opened course that is still joined** — so leaving or
/// deleting the course sitting in the slot falls back to the one opened before
/// it, rather than to an arbitrary other course (#8599). Which courses have
/// been opened is device-local view state, deliberately outside the URL.
///
/// Notifies when what the slot draws changes, and deliberately NOT when
/// ordinary traffic arrives. The nav layer rebuilds its whole subtree on a
/// notification — including whatever panel is open in the cavity — and
/// `hasRoomUpdate` is true for a read receipt or a message in any room, so
/// notifying on the raw stream would tear that panel down about once a second
/// all day.
class CourseShortcut extends ChangeNotifier {
  CourseShortcut(this._client) {
    _signature = _signatureNow;
    _updates = _client.onSync.stream
        .where((s) => s.hasRoomUpdate)
        .rateLimit(const Duration(seconds: 1))
        .listen((_) {
          final signature = _signatureNow;
          if (signature == _signature) return;
          _signature = signature;
          notifyListeners();
        });
  }

  final Client _client;
  StreamSubscription<bool>? _updates;
  String _signature = '';

  /// Course ids the learner has opened, most recent first.
  final List<String> _opened = [];

  /// Everything the slot draws, as one comparable value: each course's id,
  /// membership, name and avatar. Invited spaces count because the Courses hub
  /// sizes itself on them too. Sorted, because [Client.rooms] is
  /// recency-ordered — a message reorders it without changing what is drawn.
  String get _signatureNow =>
      (_client.rooms
              .where(
                (r) =>
                    r.isSpace &&
                    (r.membership == Membership.join ||
                        r.membership == Membership.invite),
              )
              .map((r) => '${r.id}|${r.membership.name}|${r.name}|${r.avatar}')
              .toList()
            ..sort())
          .join(',');

  /// The learner opened [courseId] — it becomes the slot's course until they
  /// open another, or leave this one. Idempotent, so a rebuild can call it
  /// freely.
  void opened(String courseId) {
    if (_opened.firstOrNull == courseId) return;
    _opened
      ..remove(courseId)
      ..insert(0, courseId);
  }

  /// The learner's joined courses, in [Client.rooms]' own recency order.
  List<Room> get courses => _client.rooms
      .where((r) => r.isSpace && r.membership == Membership.join)
      .toList();

  /// The course the slot shows — null when the learner is in none, which is
  /// the `+` add-course button. Falls through [_opened] so a course that is
  /// gone yields the one opened before it; with nothing opened still joined,
  /// the client's own recency order decides.
  Room? get course {
    final joined = courses;
    if (joined.isEmpty) return null;
    final opened = _opened.firstWhereOrNull(
      (id) => joined.any((course) => course.id == id),
    );
    return joined.firstWhere(
      (course) => course.id == opened,
      orElse: () => joined.first,
    );
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }
}

CourseShortcut? _shared;

/// The process-wide [CourseShortcut] for [client].
///
/// Shared rather than owned by the nav layer because that layer is disposed and
/// re-created whenever a map-pin sheet opens over it; a per-widget instance
/// would forget which course the learner opened every time. A different client
/// (logout, account switch) gets a fresh one, so one account's history can
/// never surface in another's slot.
CourseShortcut courseShortcutFor(Client client) {
  final shared = _shared;
  if (shared != null && shared._client == client) return shared;
  shared?.dispose();
  return _shared = CourseShortcut(client);
}
