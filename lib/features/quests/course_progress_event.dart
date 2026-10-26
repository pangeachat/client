import 'package:collection/collection.dart';

import 'package:fluffychat/features/quests/can_do_progress.dart';

/// One course's Mission figures as the learner's app shows them, stored in
/// their analytics room for the teacher dashboard so it reads the app's
/// numbers instead of rebuilding them (client#9643). A `pangea.course_progress`
/// state event whose state key is the course room id.
class CourseProgressEvent {
  final DateTime computedAt;
  final String appVersion;

  /// The XP that completes a Mission in the course when this was written, so
  /// the dashboard can tell when a [CanDoProgress.completed] is out of date.
  final int xpToComplete;

  /// Every Mission the course carries, by Mission id.
  final Map<String, CanDoProgress> canDos;

  const CourseProgressEvent({
    required this.computedAt,
    required this.appVersion,
    required this.xpToComplete,
    required this.canDos,
  });

  static const _computedAtKey = 'computed_at';
  static const _appVersionKey = 'app_version';
  static const _xpToCompleteKey = 'xp_to_complete';
  static const _canDosKey = 'can_dos';

  /// Null when [json] isn't a record: it is read from room state another
  /// device may have written. An entry that can't be read is left out.
  static CourseProgressEvent? fromJson(Map<String, Object?> json) {
    final canDos = json[_canDosKey];
    final computedAt = json[_computedAtKey];
    final xpToComplete = json[_xpToCompleteKey];
    if (canDos is! Map || computedAt is! String || xpToComplete is! num) {
      return null;
    }
    final at = DateTime.tryParse(computedAt);
    if (at == null) return null;
    final appVersion = json[_appVersionKey];
    return CourseProgressEvent(
      computedAt: at.toUtc(),
      appVersion: appVersion is String ? appVersion : '',
      xpToComplete: xpToComplete.toInt(),
      canDos: {
        for (final entry in canDos.entries)
          if (entry.key is String)
            entry.key as String: ?CanDoProgress.fromJson(entry.value),
      },
    );
  }

  Map<String, Object?> toJson() => {
    _computedAtKey: computedAt.toUtc().toIso8601String(),
    _appVersionKey: appVersion,
    ..._figures,
  };

  /// Everything but when and by which version it was written.
  Map<String, Object?> get _figures => {
    _xpToCompleteKey: xpToComplete,
    _canDosKey: {
      for (final entry in canDos.entries) entry.key: entry.value.toJson(),
    },
  };

  /// The record that follows [stored], from [canDos] as the app shows them
  /// now with no dates set. Completion dates carry over from [stored]
  /// ([CanDoProgress.datedAfter]).
  static CourseProgressEvent after({
    required CourseProgressEvent? stored,
    required int xpToComplete,
    required Map<String, CanDoProgress> canDos,
    required DateTime now,
    required String appVersion,
  }) => CourseProgressEvent(
    computedAt: now,
    appVersion: appVersion,
    xpToComplete: xpToComplete,
    canDos: {
      for (final entry in canDos.entries)
        entry.key: entry.value.datedAfter(stored?.canDos[entry.key], now),
    },
  );

  /// Whether any figure differs from [stored]'s, when and by which version
  /// each was written aside — a record that doesn't is not written.
  bool changedSince(CourseProgressEvent? stored) =>
      stored == null ||
      !const DeepCollectionEquality().equals(stored._figures, _figures);

  /// The Missions whose date is to be replayed from history
  /// ([CanDoProgress.awaitsReplay]).
  List<String> get awaitingReplay => [
    for (final entry in canDos.entries)
      if (entry.value.awaitsReplay) entry.key,
  ];

  /// This record with the replayed [dates] filled in, by Mission id. Only a
  /// missing date is filled; a date already set is never replaced.
  CourseProgressEvent withReplayedDates(Map<String, DateTime> dates) =>
      CourseProgressEvent(
        computedAt: computedAt,
        appVersion: appVersion,
        xpToComplete: xpToComplete,
        canDos: {
          for (final entry in canDos.entries)
            entry.key: switch (dates[entry.key]) {
              final at? when entry.value.awaitsReplay =>
                entry.value.withReplayedDate(at),
              _ => entry.value,
            },
        },
      );
}
