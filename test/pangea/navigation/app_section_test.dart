import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/navigation/app_section.dart';

void main() {
  AppSection from(String location) => AppSection.fromUri(Uri.parse(location));

  group('AppSection.fromUri', () {
    test('world home and matrix rooms select chats', () {
      expect(from('/'), AppSection.chats);
      expect(from('/rooms/!abc:server.org'), AppSection.chats);
    });

    test('section roots select themselves', () {
      expect(from('/analytics'), AppSection.analytics);
      expect(from('/analytics/vocab/abc'), AppSection.analytics);
      expect(from('/courses'), AppSection.courses);
      expect(from('/courses/!s:x/activity/a'), AppSection.courses);
      expect(from('/settings/security'), AppSection.settings);
      expect(from('/profile'), AppSection.profile);
    });

    test('first-class world objects select chats (world surface)', () {
      expect(from('/32ad3c08-e501-41c5-b544-0875026090ed'), AppSection.chats);
    });

    test('exact segments only — no substring leakage', () {
      // The old contains() hacks would light analytics for this.
      expect(from('/courses/analytics-course-name'), AppSection.courses);
    });
  });

  group('AppSection.activeSpaceId', () {
    test('joined course spaces are detected', () {
      expect(
        AppSection.activeSpaceId(Uri.parse('/courses/!s:x/details')),
        '!s:x',
      );
    });

    test('literal course flows are not space ids', () {
      expect(AppSection.activeSpaceId(Uri.parse('/courses/own')), isNull);
      expect(AppSection.activeSpaceId(Uri.parse('/courses')), isNull);
      expect(
        AppSection.activeSpaceId(Uri.parse('/courses/preview/!r:x')),
        isNull,
      );
    });
  });
}
