import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';

void main() {
  // Avatar reads Environment.botName (dotenv) while building; load a stub env
  // so the widget under test builds the same way it does in the app.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(mergeWith: {'BOT_NAME': 'Pangea Bot'}));

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, child: Center(child: child)),
    ),
  );

  group('AddCourseTile (#8001)', () {
    // "Start My Own" and "Browse Public Courses" tiles are backed by content
    // types (CoursePlan / Preview) with no underlying room, so their
    // unreadCoursePingEvent and courseChildrenIds are null. #7972 force-
    // unwrapped both, throwing a null-check error that rendered as a grey box.
    testWidgets('renders content with no room without throwing', (
      tester,
    ) async {
      final content = CombinedAddCourseTileContent(title: 'Intro Spanish');
      expect(content.unreadCoursePingEvent, isNull);
      expect(content.courseChildrenIds, isNull);

      await tester.pumpWidget(wrap(AddCourseTile(content: content)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Intro Spanish'), findsOneWidget);
    });
  });
}
