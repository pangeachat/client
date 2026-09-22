import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/spaces/course_search.dart';

/// Coverage for the Courses hub search (#9207): a query matches a course's
/// title, description, or CEFR level title, ignoring capitalization and
/// diacritics, and results rank title → description → level, each keeping the
/// hub's activity order.
void main() {
  const courses = {
    'Español 101': CourseSearchText(
      title: 'Español 101',
      description: 'Un viaje por el mundo hispano',
      level: 'Novice Mid (A1)',
    ),
    'German Travel': CourseSearchText(
      title: 'German Travel',
      description: 'Talk your way through Spain and Austria',
      level: 'Intermediate Low (B1)',
    ),
    'Korean Basics': CourseSearchText(
      title: 'Korean Basics',
      description: 'Hangul and greetings',
      level: 'Novice Mid (A1)',
    ),
    'Spanish Kitchen': CourseSearchText(
      title: 'Spanish Kitchen',
      description: 'Cook and chat',
    ),
  };

  List<String> search(String query, {List<String>? order}) =>
      CourseSearchText.rank(
        order ?? courses.keys.toList(),
        query,
        (name) => courses[name]!,
      );

  test('a blank query keeps every course in order', () {
    expect(search(''), courses.keys.toList());
    expect(search('   '), courses.keys.toList());
  });

  test('ignores capitalization and diacritics on both sides', () {
    expect(search('ESPANOL'), ['Español 101']);
    expect(search('Hispáno'), ['Español 101']);
  });

  test('matches the level title the tile shows', () {
    expect(search('novice mid'), ['Español 101', 'Korean Basics']);
    expect(search('b1'), ['German Travel']);
  });

  test('a course whose level has not resolved matches no level', () {
    expect(search('a1'), isNot(contains('Spanish Kitchen')));
  });

  test('ranks title matches, then description, then level', () {
    const ranked = {
      'Alpha': CourseSearchText(
        title: 'Alpha',
        description: 'First steps',
        level: 'Travel B1',
      ),
      'Beta': CourseSearchText(title: 'Beta', description: 'Travel stories'),
      'Travel Gamma': CourseSearchText(
        title: 'Travel Gamma',
        description: 'Third',
      ),
      'Delta': CourseSearchText(title: 'Delta', description: 'No match'),
    };

    expect(
      CourseSearchText.rank(
        ranked.keys.toList(),
        'travel',
        (name) => ranked[name]!,
      ),
      ['Travel Gamma', 'Beta', 'Alpha'],
    );
  });

  test('each rank keeps the incoming activity order', () {
    expect(search('novice', order: ['Korean Basics', 'Español 101']), [
      'Korean Basics',
      'Español 101',
    ]);
  });

  test('a course matching several fields appears once, at its best rank', () {
    // "Español 101" matches "a" in its title, description and level.
    expect(search('a'), courses.keys.toList());
  });
}
