import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/own/selected_course_view.dart';

/// A course space whose quest plan is confirmed gone (404) is a known state,
/// not breakage: the learner is told the course is no longer available, and
/// only an admin is offered a new course plan (#7479, #380).
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('course plan tab', () {
    testWidgets('an admin is offered a new course plan', (tester) async {
      await pump(
        tester,
        QuestLoadErrorView(MissingQuestException(), showAddCourse: true),
      );

      expect(
        find.text(
          'This course is no longer available. Pick a new course plan.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add a course plan'), findsOneWidget);
    });

    testWidgets('a member is told the course is gone, with no re-select', (
      tester,
    ) async {
      await pump(
        tester,
        QuestLoadErrorView(MissingQuestException(), showAddCourse: false),
      );

      expect(find.text('This course is no longer available'), findsOneWidget);
      expect(find.text('Add a course plan'), findsNothing);
    });

    testWidgets('any other failure stays a generic error', (tester) async {
      await pump(
        tester,
        QuestLoadErrorView(Exception('network'), showAddCourse: true),
      );

      expect(find.byType(ErrorIndicator), findsOneWidget);
      expect(find.text('Add a course plan'), findsNothing);
    });
  });

  group('course preview', () {
    Widget view({String? unavailableMessage}) => SelectedCourseView(
      title: 'Join course',
      hasError: true,
      unavailableMessage: unavailableMessage,
      onTapCta: () {},
      ctaButtonText: 'Join',
    );

    testWidgets('a course that is gone says so, with no join button', (
      tester,
    ) async {
      await pump(
        tester,
        view(unavailableMessage: 'This course is no longer available'),
      );

      expect(find.text('This course is no longer available'), findsOneWidget);
      expect(find.byType(ErrorIndicator), findsNothing);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('a link to no course says not found', (tester) async {
      await pump(tester, view(unavailableMessage: 'Course not found'));

      expect(find.text('Course not found'), findsOneWidget);
      expect(find.byType(ErrorIndicator), findsNothing);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('any other failure stays a generic error', (tester) async {
      await pump(tester, view());

      expect(find.byType(ErrorIndicator), findsOneWidget);
      expect(find.text('Course not found'), findsNothing);
    });
  });
}
