import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/activity_family.dart';

/// The family helper (Content Studio v2): every member of an activity family
/// maps to ONE id — the first shown member in course order, else the first
/// removed member — and per-member values are summed onto it.
void main() {
  ListedActivity act(
    String id, [
    List<String> family = const [],
    bool shown = true,
  ]) => ListedActivity(activityId: id, familyIds: family, shown: shown);

  group('activityFamily', () {
    test('an activity with no copy is its own family', () {
      expect(
        activityFamily([
          act('a1', ['a1']),
        ]),
        {'a1': 'a1'},
      );
    });

    test('a missing family list reads as just the activity', () {
      expect(activityFamily([act('a1')]), {'a1': 'a1'});
    });

    test('the shown copy is canonical for its whole family', () {
      expect(
        activityFamily([
          act('c1', ['a1', 'c1']),
        ]),
        {'a1': 'c1', 'c1': 'c1'},
      );
    });

    test('a copy of a copy resolves to the one shown id', () {
      expect(
        activityFamily([
          act('c2', ['a1', 'c1', 'c2']),
        ]),
        {'a1': 'c2', 'c1': 'c2', 'c2': 'c2'},
      );
    });

    test('a shown member beats an earlier removed one', () {
      // Course order lists a Can-Do's removed ids after its shown ones, but a
      // removed id of an earlier Can-Do comes first overall.
      final family = activityFamily([
        act('c1', ['a1', 'c1'], false),
        act('a1', ['a1', 'c1']),
      ]);
      expect(family, {'a1': 'a1', 'c1': 'a1'});
    });

    test('with no shown member the first removed one is canonical', () {
      final family = activityFamily([
        act('c1', ['a1', 'c1'], false),
        act('a1', ['a1', 'c1'], false),
      ]);
      expect(family, {'a1': 'c1', 'c1': 'c1'});
    });

    test('listings that each name part of a family still merge', () {
      final family = activityFamily([
        act('a1', ['a1', 'c1']),
        act('c2', ['c1', 'c2']),
      ]);
      expect(family.values.toSet(), {'a1'});
      expect(family.keys.toSet(), {'a1', 'c1', 'c2'});
    });

    test('separate families stay separate', () {
      final family = activityFamily([
        act('a1', ['a1']),
        act('a2', ['a2']),
      ]);
      expect(family, {'a1': 'a1', 'a2': 'a2'});
    });
  });

  group('creditByShown', () {
    test('sums members onto the shown id', () {
      final family = {'a1': 'c1', 'c1': 'c1'};
      expect(creditByShown({'a1': 2, 'c1': 3}, family), {'c1': 5});
    });

    test('drops members the family does not name', () {
      expect(creditByShown({'a1': 2, 'zzz': 9}, {'a1': 'a1'}), {'a1': 2});
    });

    test('carries fractional values (XP)', () {
      expect(creditByShown({'a': 1.5, 'b': 2}, {'a': 'b', 'b': 'b'}), {
        'b': 3.5,
      });
    });
  });

  group('CourseCredit', () {
    test('none credits nothing new and returns the map untouched', () {
      final raw = {'a1': 2};
      expect(identical(CourseCredit.none.creditedBy(raw), raw), isTrue);
      expect(CourseCredit.none.starsFor('a1', raw), 2);
      expect(CourseCredit.none.starsFor('zzz', raw), 0);
    });

    test('starsFor reads the credited sum on the shown id', () {
      const credit = CourseCredit(family: {'a1': 'c1', 'c1': 'c1'});
      expect(credit.starsFor('c1', {'a1': 2, 'c1': 3}), 5);
    });

    test('starsFor gives every member of a family the family total', () {
      // A family shown in two Can-Dos: both cards read the same number.
      const credit = CourseCredit(family: {'a1': 'a1', 'c1': 'a1'});
      expect(credit.starsFor('a1', {'a1': 2, 'c1': 1}), 3);
      expect(credit.starsFor('c1', {'a1': 2, 'c1': 1}), 3);
    });

    test('starsFor leaves an activity the course does not credit alone', () {
      const credit = CourseCredit(family: {'a1': 'a1'});
      expect(credit.starsFor('elsewhere', {'elsewhere': 4}), 4);
    });

    test('overlayOn raises the canonical id and keeps every other entry', () {
      const credit = CourseCredit(family: {'a1': 'c1', 'c1': 'c1'});
      expect(credit.overlayOn({'a1': 2, 'c1': 3, 'x': 1}), {
        'a1': 2,
        'c1': 5,
        'x': 1,
      });
      // A canonical id with no stars of its own gains the original's.
      expect(credit.overlayOn({'a1': 2}), {'a1': 2, 'c1': 2});
    });

    test('overlayOn also raises a shown member that is not canonical', () {
      // A family shown in two Can-Dos: the pin for each reads the total.
      const credit = CourseCredit(
        family: {'a1': 'a1', 'c1': 'a1'},
        shownIds: {'a1', 'c1'},
      );
      expect(credit.overlayOn({'a1': 2}), {'a1': 2, 'c1': 2});
      expect(credit.overlayOn({'a1': 2, 'c1': 1}), {'a1': 3, 'c1': 3});
    });

    test('overlayOn leaves a hidden member at its own stars', () {
      const credit = CourseCredit(
        family: {'a1': 'c1', 'c1': 'c1'},
        shownIds: {'c1'},
      );
      expect(credit.overlayOn({'a1': 2, 'c1': 1}), {'a1': 2, 'c1': 3});
    });
  });
}
