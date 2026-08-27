import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/panel_focus.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
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
  CourseShortcut._();

  /// One per process, like [PanelFocusController]: the nav layer is disposed
  /// and re-created whenever a map-pin sheet opens over it, and a per-widget
  /// instance would forget which course the learner opened every time.
  static final CourseShortcut instance = CourseShortcut._();

  Client? _client;
  StreamSubscription<bool>? _updates;
  String _signature = '';

  /// Course ids the learner has opened, most recent first.
  final List<String> _opened = [];

  /// Starts watching [client] for the changes the slot cares about. Re-pointing
  /// at a different client (logout, account switch) drops the opened-course
  /// memory, so one account's history can never surface in another's slot.
  void watch(Client client) {
    if (identical(_client, client)) return;
    _updates?.cancel();
    _client = client;
    _opened.clear();
    _signature = _signatureNow;
    _updates = client.onSync.stream
        .where((s) => s.hasRoomUpdate)
        .rateLimit(const Duration(seconds: 1))
        .listen((_) {
          final signature = _signatureNow;
          if (signature == _signature) return;
          _signature = signature;
          notifyListeners();
        });
  }

  /// Everything the slot draws, as one comparable value: each course's id,
  /// membership, name and avatar. Invited spaces count because the Courses hub
  /// sizes itself on them too. Sorted, because [Client.rooms] is
  /// recency-ordered — a message reorders it without changing what is drawn.
  String get _signatureNow =>
      (_client?.courses
              .map((r) => '${r.id}|${r.membership.name}|${r.name}|${r.avatar}')
              .toList()
            ?..sort())
          ?.join(',') ??
      '';

  /// The learner opened [courseId] — it becomes the slot's course until they
  /// open another, or leave this one. Idempotent, so a rebuild can call it
  /// freely.
  void opened(String courseId) {
    if (_opened.firstOrNull == courseId) return;
    _opened
      ..remove(courseId)
      ..insert(0, courseId);
  }

  /// The course the slot shows — null when the learner is in none, which is
  /// the `+` add-course button. Falls through [_opened] so a course that is
  /// gone yields the one opened before it; with nothing opened still joined,
  /// the client's own recency order decides.
  Room? get course {
    final joined = _client?.joinedCourses ?? const <Room>[];
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
