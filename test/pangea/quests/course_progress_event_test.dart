import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/can_do_progress.dart';
import 'package:fluffychat/features/quests/course_progress_event.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// The course progress record the teacher dashboard reads (client#9643):
/// written only when a figure changed, with a completion date that is never
/// cleared or moved and never guessed.
void main() {
  final t0 = DateTime.utc(2026, 10, 20, 15);
  final t1 = DateTime.utc(2026, 10, 26, 14);
  final t2 = DateTime.utc(2026, 10, 27, 9);

  CanDoProgress canDo(int xp, {bool completed = false}) => CanDoProgress(
    xp: xp,
    breakdown: MissionXpBreakdown(chat: xp),
    completed: completed,
  );

  /// The record the writer stores after [stored], or null when it writes
  /// nothing.
  CourseProgressEvent? write(
    CourseProgressEvent? stored,
    Map<String, CanDoProgress> canDos, {
    required DateTime now,
    int xpToComplete = 1000,
    String appVersion = '5.0.14+1',
    Map<String, DateTime> replayed = const {},
  }) {
    final next = CourseProgressEvent.after(
      stored: stored,
      xpToComplete: xpToComplete,
      canDos: canDos,
      now: now,
      appVersion: appVersion,
    ).withReplayedDates(replayed);
    return next.changedSince(stored) ? next : null;
  }

  group('replayed dates', () {
    test('fill a missing date and keep the before-tracking mark', () {
      final first = write(null, {
        'lo1': canDo(1200, completed: true),
      }, now: t1)!;
      expect(first.awaitingReplay, ['lo1']);
      final replayed = write(
        first,
        {'lo1': canDo(1200, completed: true)},
        now: t2,
        replayed: {'lo1': t0},
      )!;
      expect(replayed.canDos['lo1']!.firstCompletedAt, t0);
      expect(replayed.canDos['lo1']!.completedBeforeTracking, isTrue);
      expect(replayed.awaitingReplay, isEmpty);
    });

    test('are written in the first record when the replay runs at once', () {
      final first = write(
        null,
        {'lo1': canDo(1200, completed: true)},
        now: t1,
        replayed: {'lo1': t0},
      )!;
      expect(first.toJson()['can_dos'], {
        'lo1': {
          'xp': 1200,
          'chat': 1200,
          'speaking': 0,
          'goals': 0,
          'practice': 0,
          'completed': true,
          'first_completed_at': '2026-10-20T15:00:00.000Z',
          'completed_before_tracking': true,
        },
      });
    });

    test('are kept by later writes, mark and all', () {
      final first = write(
        null,
        {'lo1': canDo(1200, completed: true)},
        now: t1,
        replayed: {'lo1': t0},
      )!;
      final read = CourseProgressEvent.fromJson(first.toJson())!;
      final later = write(read, {
        'lo1': canDo(1300, completed: true),
      }, now: t2)!;
      expect(later.canDos['lo1']!.firstCompletedAt, t0);
      expect(later.canDos['lo1']!.completedBeforeTracking, isTrue);
      expect(later.awaitingReplay, isEmpty);
    });

    test('never replace a date the app saw', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      final done = write(first, {
        'lo1': canDo(1100, completed: true),
      }, now: t1)!;
      expect(
        done.withReplayedDates({'lo1': t0}).canDos['lo1']!.firstCompletedAt,
        t1,
      );
    });

    test('are not asked for a Mission that is not complete now', () {
      final first = write(null, {
        'lo1': canDo(1200, completed: true),
      }, now: t0)!;
      final raised = write(first, {'lo1': canDo(1200)}, now: t1)!;
      expect(raised.awaitingReplay, isEmpty);
    });
  });

  group('completion dates', () {
    test('a Mission complete at the first write gets no date', () {
      final first = write(null, {
        'lo1': canDo(1200, completed: true),
        'lo2': canDo(300),
      }, now: t1)!;
      expect(first.canDos['lo1']!.firstCompletedAt, isNull);
      expect(first.canDos['lo1']!.completedBeforeTracking, isTrue);
      expect(first.canDos['lo2']!.firstCompletedAt, isNull);
      expect(first.canDos['lo2']!.completedBeforeTracking, isFalse);
    });

    test('a Mission seen to become complete is dated then', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      final second = write(first, {
        'lo1': canDo(1100, completed: true),
      }, now: t1)!;
      expect(second.canDos['lo1']!.firstCompletedAt, t1);
      expect(second.canDos['lo1']!.completedBeforeTracking, isFalse);
    });

    test('a date is kept when XP falls below the threshold', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      final done = write(first, {
        'lo1': canDo(1100, completed: true),
      }, now: t1)!;
      final raised = write(done, {'lo1': canDo(1100)}, now: t2)!;
      expect(raised.canDos['lo1']!.completed, isFalse);
      expect(raised.canDos['lo1']!.firstCompletedAt, t1);
      final again = write(raised, {
        'lo1': canDo(1600, completed: true),
      }, now: t2.add(const Duration(days: 1)))!;
      expect(again.canDos['lo1']!.firstCompletedAt, t1);
    });

    test('a Mission marked complete before tracking stays undated', () {
      final first = write(null, {
        'lo1': canDo(1200, completed: true),
      }, now: t0)!;
      final raised = write(first, {'lo1': canDo(1200)}, now: t1)!;
      final again = write(raised, {
        'lo1': canDo(2000, completed: true),
      }, now: t2)!;
      expect(again.canDos['lo1']!.firstCompletedAt, isNull);
      expect(again.canDos['lo1']!.completedBeforeTracking, isTrue);
    });

    test('a Mission seen to become complete keeps the threshold it met', () {
      final first = write(
        null,
        {'lo1': canDo(300)},
        now: t0,
        xpToComplete: 500,
      )!;
      final done = write(
        first,
        {'lo1': canDo(600, completed: true)},
        now: t1,
        xpToComplete: 500,
      )!;
      expect(done.canDos['lo1']!.xpToCompleteAtFirstCompletion, 500);
      expect(
        done.toJson()['can_dos'],
        containsPair(
          'lo1',
          containsPair('xp_to_complete_at_first_completion', 500),
        ),
      );
      final read = CourseProgressEvent.fromJson(done.toJson())!;
      final raised = write(
        read,
        {'lo1': canDo(600, completed: true)},
        now: t2,
        xpToComplete: 1500,
      )!;
      expect(raised.canDos['lo1']!.xpToCompleteAtFirstCompletion, 500);
      expect(raised.canDos['lo1']!.firstCompletedAt, t1);
    });

    test('a Mission complete at the first write, or replayed, has none', () {
      final first = write(null, {
        'lo1': canDo(1200, completed: true),
      }, now: t1)!;
      expect(first.canDos['lo1']!.xpToCompleteAtFirstCompletion, isNull);
      final replayed = first.withReplayedDates({'lo1': t0});
      expect(replayed.canDos['lo1']!.xpToCompleteAtFirstCompletion, isNull);
      expect(
        replayed.toJson()['can_dos'],
        isNot(
          containsPair('lo1', contains('xp_to_complete_at_first_completion')),
        ),
      );
    });

    test('a Mission added to the course already complete gets no date', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      final added = write(first, {
        'lo1': canDo(300),
        'lo2': canDo(1500, completed: true),
      }, now: t1)!;
      expect(added.canDos['lo2']!.firstCompletedAt, isNull);
      expect(added.canDos['lo2']!.completedBeforeTracking, isTrue);
    });
  });

  group('when to write', () {
    test('nothing changed: no write, whatever the time or version', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      expect(
        write(first, {'lo1': canDo(300)}, now: t1, appVersion: '5.1.0+7'),
        isNull,
      );
    });

    test('a dated completion with nothing new is not rewritten', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      final done = write(first, {
        'lo1': canDo(1100, completed: true),
      }, now: t1)!;
      expect(
        write(done, {'lo1': canDo(1100, completed: true)}, now: t2),
        isNull,
      );
    });

    test('a new threshold is a change', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      expect(
        write(first, {'lo1': canDo(300)}, now: t1, xpToComplete: 500),
        isNotNull,
      );
    });

    test('a Mission the course no longer carries is a change', () {
      final first = write(null, {'lo1': canDo(300), 'lo2': canDo(0)}, now: t0)!;
      final next = write(first, {'lo1': canDo(300)}, now: t1)!;
      expect(next.canDos.keys, ['lo1']);
    });
  });

  group('stored as JSON', () {
    test('uses the dashboard\'s names', () {
      final record = write(null, {
        'lo1': CanDoProgress(
          xp: 1240,
          breakdown: const MissionXpBreakdown(
            chat: 610,
            speaking: 120,
            goals: 300,
            practice: 210,
          ),
          completed: true,
        ),
      }, now: t1)!;
      expect(record.toJson(), {
        'computed_at': '2026-10-26T14:00:00.000Z',
        'app_version': '5.0.14+1',
        'xp_to_complete': 1000,
        'can_dos': {
          'lo1': {
            'xp': 1240,
            'chat': 610,
            'speaking': 120,
            'goals': 300,
            'practice': 210,
            'completed': true,
            'first_completed_at': null,
            'completed_before_tracking': true,
          },
        },
      });
    });

    test('reads back what it wrote', () {
      final first = write(null, {'lo1': canDo(300)}, now: t0)!;
      final done = write(first, {
        'lo1': canDo(1100, completed: true),
      }, now: t1)!;
      final read = CourseProgressEvent.fromJson(done.toJson())!;
      expect(read.canDos['lo1']!.firstCompletedAt, t1);
      expect(
        write(read, {'lo1': canDo(1100, completed: true)}, now: t2),
        isNull,
      );
    });

    test('a record that is not one reads as none', () {
      expect(CourseProgressEvent.fromJson({'can_dos': 'nope'}), isNull);
      expect(CourseProgressEvent.fromJson({}), isNull);
    });

    test('an entry that is not one is left out', () {
      final read = CourseProgressEvent.fromJson({
        'computed_at': '2026-10-26T14:00:00.000Z',
        'app_version': '5.0.14+1',
        'xp_to_complete': 1000,
        'can_dos': {
          'lo1': {'xp': 10, 'chat': 10, 'completed': false},
          'lo2': 'nope',
        },
      })!;
      expect(read.canDos.keys, ['lo1']);
      expect(read.canDos['lo1']!.xp, 10);
    });
  });
}
