import 'package:flutter/material.dart' hide Visibility;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_access_sheet.dart';
import 'package:fluffychat/routes/courses/own/course_creation_settings_widget.dart';
import 'package:fluffychat/routes/courses/own/selected_course_view.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The three course access settings and the one sheet that picks them —
/// joining-courses.instructions.md § Course access (#9359).
void main() {
  group('CourseAccess.fromSettings', () {
    test('each setting is its own pair of directory listing and join rule', () {
      for (final access in CourseAccess.values) {
        expect(
          CourseAccess.fromSettings(access.visibility, access.joinRule),
          access,
        );
      }
    });

    test('a pair that matches none of the three selects nothing', () {
      // The old Access page allowed an unlisted course anyone could join.
      expect(
        CourseAccess.fromSettings(Visibility.private, JoinRules.public),
        isNull,
      );
      expect(
        CourseAccess.fromSettings(Visibility.public, JoinRules.invite),
        isNull,
      );
      expect(CourseAccess.fromSettings(null, JoinRules.knock), isNull);
    });

    test('new courses start on approval required', () {
      expect(CourseAccess.initial, CourseAccess.approvalRequired);
    });
  });

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: home,
  );

  group('CourseAccessSheet', () {
    late CourseAccess? result;
    late bool closed;

    Future<void> openSheet(WidgetTester tester, CourseAccess? initial) async {
      closed = false;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await CourseAccessSheet.show(context, initial);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('Done returns the setting the teacher picked', (tester) async {
      await openSheet(tester, CourseAccess.approvalRequired);

      expect(find.text('Who can join?'), findsOneWidget);
      expect(
        find.text(
          'Students with your course code or an invite can join '
          'right away, whatever you choose.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Private'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, CourseAccess.private);
    });

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      await openSheet(tester, CourseAccess.approvalRequired);

      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('with nothing selected yet, Done waits for a choice', (
      tester,
    ) async {
      await openSheet(tester, null);

      final done = find.widgetWithText(FilledButton, 'Done');
      expect(tester.widget<FilledButton>(done).onPressed, isNull);

      await tester.tap(find.text('Approval required'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
    });
  });

  group('the create-course preview', () {
    final plan = CoursePlanModel(
      uuid: 'quest-1',
      title: 'Elementary German I',
      description: 'STEM and professional life.',
      targetLanguage: 'de',
      languageOfInstructions: 'en',
      cefrLevel: LanguageLevelTypeEnum.a1,
      topicIds: const [],
      mediaIds: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    Future<void> pumpPreview(
      WidgetTester tester, {
      required double height,
      bool creating = true,
      ValueChanged<bool>? onChangedRequireAnalyticsAccess,
    }) async {
      tester.view.physicalSize = Size(400, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          SelectedCourseView(
            title: 'New course',
            course: plan,
            onTapCta: () {},
            ctaButtonText: 'Create course',
            creationSettings: creating
                ? CourseCreationSettings(
                    access: CourseAccess.initial,
                    onTapAccess: () {},
                    requireAnalyticsAccess: true,
                    onChangedRequireAnalyticsAccess:
                        onChangedRequireAnalyticsAccess ?? (_) {},
                  )
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const analyticsTitle = 'Require analytics access to join';
    const analyticsSummary =
        'Students share their learning progress with you when they join.';

    testWidgets('shows both settings above Create course at its rest', (
      tester,
    ) async {
      // Tall enough for the header, both rows and the CTA, but still the
      // resting height: the description is dropped.
      await pumpPreview(tester, height: 340);

      expect(find.text('Who can join?'), findsOneWidget);
      expect(find.text('Approval required'), findsOneWidget);
      expect(find.text(analyticsTitle), findsOneWidget);
      expect(find.text(analyticsSummary), findsOneWidget);
      expect(find.text('STEM and professional life.'), findsNothing);
      expect(
        tester.getBottomLeft(find.text('Approval required')).dy,
        lessThan(tester.getTopLeft(find.text(analyticsTitle)).dy),
      );
      expect(
        tester.getBottomLeft(find.text(analyticsSummary)).dy,
        lessThan(tester.getTopLeft(find.text('Create course')).dy),
      );
    });

    testWidgets('the analytics switch reports the new value', (tester) async {
      bool? changedTo;
      await pumpPreview(
        tester,
        height: 340,
        onChangedRequireAnalyticsAccess: (value) => changedTo = value,
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(changedTo, isFalse);
    });

    testWidgets('tapping anywhere on the analytics row flips the switch', (
      tester,
    ) async {
      bool? changedTo;
      await pumpPreview(
        tester,
        height: 340,
        onChangedRequireAnalyticsAccess: (value) => changedTo = value,
      );

      await tester.tap(find.text(analyticsSummary));
      await tester.pumpAndSettle();

      expect(changedTo, isFalse);
    });

    testWidgets('the analytics subtitle shows in full on a phone', (
      tester,
    ) async {
      await pumpPreview(tester, height: 340);

      final summary = tester.widget<Text>(find.text(analyticsSummary));
      expect(summary.maxLines, isNull);
      expect(summary.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('the analytics row reads as one switch', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPreview(tester, height: 340);

      final node = tester.getSemantics(find.byType(Switch));
      expect(node.label, contains(analyticsTitle));
      expect(node.label, contains(analyticsSummary));
      semantics.dispose();
    });

    testWidgets('a rest too short for the rows keeps Create course in view', (
      tester,
    ) async {
      // Long copy or large text can make the rows taller than the rest
      // allows; they clip at the top instead of overflowing.
      await pumpPreview(tester, height: 200);

      expect(tester.takeException(), isNull);
      final createBottom = tester.getBottomLeft(find.text('Create course')).dy;
      expect(createBottom, lessThanOrEqualTo(200));
    });

    testWidgets('a preview that does not create a course has no settings', (
      tester,
    ) async {
      await pumpPreview(tester, height: 800, creating: false);

      expect(find.text('Create course'), findsOneWidget);
      expect(find.text('Who can join?'), findsNothing);
      expect(find.text(analyticsTitle), findsNothing);
    });
  });
}
