import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/analytics_sharing_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_avatar.dart';
import 'package:fluffychat/routes/settings/settings_learning/shared_analytics_section.dart';
import 'get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const courseId = '!course:fakeServer.notExisting';
  const teacherId = '@rivera:fakeServer.notExisting';

  late Client client;

  setUpAll(() async {
    // Avatar compares against BotName.byEnvironment, which reads GetStorage
    // (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('shared_section');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  // Created outside the widget test's fake clock: the client's setup is real
  // I/O, which never completes inside it.
  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  testWidgets('a shared course shows its avatar and opens its course page', (
    tester,
  ) async {
    final course = Room(
      id: courseId,
      client: client,
      membership: Membership.join,
    );
    course.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': 'Spanish 101'},
        senderId: '@teacher:fakeServer.notExisting',
        eventId: '\$name',
        originServerTs: DateTime.utc(2026, 1, 1),
        stateKey: '',
        room: course,
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SharedCourseTile(
              shared: SharedCourse(
                course: course,
                teachers: [
                  User(teacherId, displayName: 'Ms Rivera', room: course),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CourseAvatar), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    // The course's teacher who can see the learner's progress, under it.
    expect(find.text('Ms Rivera'), findsOneWidget);

    await tester.tap(find.text('Spanish 101'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      WorkspaceNav.openCourse(Uri.parse('/'), courseId),
    );
  });
}
