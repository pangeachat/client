import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/world/activity_course_resolver.dart';
import 'get_test_client.dart';

/// source_course_id must be a genuinely-pinned course, never an arbitrary pick.
/// When an activity is opened without a selected course, it is attributed to a
/// matching course only when the match is UNAMBIGUOUS (exactly one).
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room room(String id) => Room(id: id, client: client);

  test('pins only when exactly one course matches; a tie is unscoped', () {
    expect(
      ActivityCourseResolver.unambiguousCourseId([]),
      isNull,
      reason: 'no match → unscoped',
    );
    expect(
      ActivityCourseResolver.unambiguousCourseId([room('!c1:example.org')]),
      '!c1:example.org',
      reason: 'exactly one match → that course',
    );
    expect(
      ActivityCourseResolver.unambiguousCourseId([
        room('!c1:example.org'),
        room('!c2:example.org'),
      ]),
      isNull,
      reason: 'ambiguous → unscoped, never an arbitrary firstOrNull pick',
    );
  });
}
