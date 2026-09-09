import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/map_context.dart';

// The course preview's map scope (#7826): a CourseMapContext subtype the map
// treats as course-scoped, distinguished for the preview-only behavior
// (auto-fit, banner, inert pins), plus the browse flow's room → plan-uuid
// resolution registry. See course-preview.instructions.md.
void main() {
  tearDown(() {
    MapContextController.set(const WorldMapContext());
    CoursePreviewPlans.clear('!room');
  });

  group('CoursePreviewMapContext', () {
    test('is a course scope, but never equal to the plain one', () {
      const plain = CourseMapContext('plan-uuid');
      const preview = CoursePreviewMapContext('plan-uuid');
      expect(preview, isA<CourseMapContext>());
      // Distinct in both directions — otherwise the context notifier would
      // treat a plain→preview scope change on the same plan as a no-op and
      // the map would never learn it is previewing.
      expect(preview == plain, isFalse);
      expect(plain == preview, isFalse);
      expect(
        const CoursePreviewMapContext('plan-uuid'),
        const CoursePreviewMapContext('plan-uuid'),
      );
      expect(
        const CoursePreviewMapContext('a'),
        isNot(const CoursePreviewMapContext('b')),
      );
    });

    test('re-scoping the same plan from joined to preview notifies', () {
      MapContextController.set(const CourseMapContext('plan-uuid'));
      MapContextController.set(const CoursePreviewMapContext('plan-uuid'));
      expect(
        MapContextController.notifier.value,
        isA<CoursePreviewMapContext>(),
      );
    });
  });

  group('CoursePreviewPlans', () {
    test('publish stores the resolution and scopes the live map', () {
      CoursePreviewPlans.publish('!room', 'plan-uuid');
      expect(CoursePreviewPlans.planIdFor('!room'), 'plan-uuid');
      expect(
        MapContextController.notifier.value,
        const CoursePreviewMapContext('plan-uuid'),
      );
    });

    test('clear forgets the resolution', () {
      CoursePreviewPlans.publish('!room', 'plan-uuid');
      CoursePreviewPlans.clear('!room');
      expect(CoursePreviewPlans.planIdFor('!room'), isNull);
    });

    test('an unknown room resolves to null (map keeps its current scope)', () {
      expect(CoursePreviewPlans.planIdFor('!unknown'), isNull);
      expect(CoursePreviewPlans.planIdFor(null), isNull);
    });
  });
}
