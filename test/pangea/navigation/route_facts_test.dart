import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

void main() {
  AppSection section(String location) => sectionFor(Uri.parse(location));
  String? space(String location) => activeSpaceIdFor(Uri.parse(location));

  group('sectionFor', () {
    test('root selects world; matrix rooms select chats', () {
      expect(section('/'), AppSection.world);
      expect(section('/chats'), AppSection.chats);
      expect(section('/rooms/!abc:server.org'), AppSection.chats);
    });

    test('section roots select themselves; a course room stays in courses', () {
      expect(section('/analytics'), AppSection.analytics);
      expect(section('/analytics/vocab/abc'), AppSection.analytics);
      expect(section('/courses'), AppSection.courses);
      // The nested course chat room is still the courses section, not chats —
      // the split this rebuild fixes.
      expect(section('/courses/!s:x/!room:x'), AppSection.courses);
      expect(section('/settings/security'), AppSection.settings);
      expect(section('/profile'), AppSection.profile);
    });

    test('first-class world objects (uuid) select world', () {
      expect(section('/32ad3c08-e501-41c5-b544-0875026090ed'), AppSection.world);
    });

    test('exact segments only — no substring leakage', () {
      expect(section('/courses/analytics-course-name'), AppSection.courses);
    });
  });

  group('activeSpaceIdFor', () {
    test('joined course spaces are detected (root, detail, overlay, room)', () {
      expect(space('/courses/!s:x'), '!s:x');
      expect(space('/courses/!s:x/details'), '!s:x');
      expect(space('/courses/!s:x?activity=a'), '!s:x');
      expect(space('/courses/!s:x/!room:x'), '!s:x');
    });

    test('literal course flows and preview are not space ids', () {
      expect(space('/courses/own'), isNull);
      expect(space('/courses'), isNull);
      // preview's room id must never masquerade as the active space.
      expect(space('/courses/preview/!r:x'), isNull);
    });
  });

  group('isMapHole', () {
    test('world is always the map hole, in both modes', () {
      expect(isMapHole('/', false), isTrue);
      expect(isMapHole('/', true), isTrue);
    });

    test('section roots are map holes in column mode only', () {
      expect(isMapHole('/chats', true), isTrue);
      expect(isMapHole('/chats', false), isFalse);
      expect(isMapHole('/courses/:spaceid', true), isTrue);
      expect(isMapHole('/analytics/morph', true), isTrue);
    });

    test('the add-course hub and detail routes are not map holes', () {
      expect(isMapHole('/courses', true), isFalse); // full-bleed
      expect(isMapHole('/courses/:spaceid/:roomid', true), isFalse); // detail
      expect(isMapHole('/rooms/:roomid', true), isFalse); // detail
    });
  });
}
