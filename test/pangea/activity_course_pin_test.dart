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
      ActivityCourseResolver.unambiguousCourseId((
        matches: const [],
        complete: true,
      )),
      isNull,
      reason: 'no match → unscoped',
    );
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: [room('!c1:example.org')],
        complete: true,
      )),
      '!c1:example.org',
      reason: 'exactly one match, set complete → that course',
    );
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: [room('!c1:example.org'), room('!c2:example.org')],
        complete: true,
      )),
      isNull,
      reason: 'ambiguous → unscoped, never an arbitrary firstOrNull pick',
    );
  });

  test('a lone match from an INCOMPLETE set is not pinned', () {
    // Another joined course failed to resolve its quest, so this single
    // surviving match might not actually be unique — do not pin it.
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: [room('!c1:example.org')],
        complete: false,
      )),
      isNull,
      reason:
          'a lone survivor of a batch with an unresolved course must stay '
          'unscoped — it could mis-attribute source_course_id',
    );
  });
}
