import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/spaces/public_course_extension.dart';

/// Start my own sends a learner to a course they can join before letting them
/// make their own (#9590): the language's central course, else the biggest
/// public course already on the picked quest.
void main() {
  PublicCoursesChunk course(
    String id, {
    String quest = 'quest-1',
    String joinRule = 'public',
    int members = 1,
    bool? central,
  }) => PublicCoursesChunk.tryParse({
    'room_id': id,
    'num_joined_members': members,
    'world_readable': true,
    'guest_can_join': false,
    'join_rule': joinRule,
    'course_id': quest,
    'central': ?central,
  })!;

  group('PublicCoursesChunk.central', () {
    test('reads the catalog mark', () {
      expect(course('!a', central: true).central, isTrue);
      expect(course('!a', central: false).central, isFalse);
    });

    test('a catalog that predates the mark reads as not central', () {
      expect(course('!a').central, isFalse);
    });
  });

  group('PublicCoursesChunk.toJoinInstead', () {
    test('the central course wins, even on another quest', () {
      final picked = PublicCoursesChunk.toJoinInstead([
        course('!big', members: 50),
        course('!central', quest: 'quest-2', central: true),
      ], 'quest-1');
      expect(picked?.room.roomId, '!central');
    });

    test('without one, the public course on the quest with most members', () {
      final picked = PublicCoursesChunk.toJoinInstead([
        course('!small', members: 2),
        course('!big', members: 9),
        course('!other-quest', quest: 'quest-2', members: 40),
      ], 'quest-1');
      expect(picked?.room.roomId, '!big');
    });

    test('a course you must ask to join does not count', () {
      final picked = PublicCoursesChunk.toJoinInstead([
        course('!knock', joinRule: 'knock', members: 30),
        course('!open', members: 3),
      ], 'quest-1');
      expect(picked?.room.roomId, '!open');
    });

    test('nothing to join leaves the learner to create', () {
      expect(
        PublicCoursesChunk.toJoinInstead([
          course('!knock', joinRule: 'knock'),
          course('!other-quest', quest: 'quest-2'),
        ], 'quest-1'),
        isNull,
      );
      expect(PublicCoursesChunk.toJoinInstead([], 'quest-1'), isNull);
    });

    test('two central courses in a language: the bigger one', () {
      final picked = PublicCoursesChunk.toJoinInstead([
        course('!central-small', central: true, members: 4),
        course('!central-big', central: true, members: 12),
      ], 'quest-1');
      expect(picked?.room.roomId, '!central-big');
    });
  });

  group('PublicCoursesChunk.centralOf (#9591)', () {
    test('the central course, the bigger one when there are two', () {
      expect(
        PublicCoursesChunk.centralOf([
          course('!public', members: 50),
          course('!central-small', central: true, members: 4),
          course('!central-big', central: true, members: 12),
        ])?.room.roomId,
        '!central-big',
      );
    });

    test('no central course is none, however big the rest', () {
      expect(
        PublicCoursesChunk.centralOf([course('!public', members: 50)]),
        isNull,
      );
    });
  });
}
