import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/spaces/public_course_extension.dart';

typedef _Course = ({String name, int members, String rule});

List<String> _rank(List<_Course> courses, String query) => [
  for (final c in rankCoursesByName(
    courses,
    query,
    name: (c) => c.name,
    members: (c) => c.members,
    joinRule: (c) => c.rule,
  ))
    c.name,
];

/// The course search's one match and order, shared by the add-course list
/// and the world view.
void main() {
  const courses = <_Course>[
    (name: 'Advanced Spanish', members: 9, rule: 'knock'),
    (name: 'Spanish 1', members: 3, rule: 'knock'),
    (name: 'Spanish 2', members: 3, rule: 'public'),
    (name: 'German', members: 20, rule: 'public'),
  ];

  test('matches on a case-folded name, starts-with first', () {
    expect(_rank(courses, 'spanish'), [
      'Spanish 2',
      'Spanish 1',
      'Advanced Spanish',
    ]);
  });

  test('then more members, then open before ask-to-join', () {
    expect(_rank(courses, ''), [
      'German',
      'Advanced Spanish',
      'Spanish 2',
      'Spanish 1',
    ]);
  });

  test('a query matching nothing keeps nothing', () {
    expect(_rank(courses, 'french'), isEmpty);
  });
}
