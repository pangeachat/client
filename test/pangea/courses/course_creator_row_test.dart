import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_creator_row.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

/// The course page credits whoever made the course, from the quest the page is
/// already loading. The credit follows the quest's own owner — Pangea's name
/// only over Pangea's own courses.
///
/// The credit is a **labelled detail** here, not a bare name row: it lives in
/// the More section among the course's settings, where an unlabelled avatar
/// would read as a person to contact or a control to tap rather than as
/// attribution (#8819).
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const teacher = '@profeceniza02:pangea.chat';

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    await client.database.storeUserProfile(
      teacher,
      CachedProfileInformation.fromProfile(
        ProfileInformation(displayname: 'Señora Díaz'),
        outdated: false,
        updated: DateTime.now(),
      ),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(() async {
    UserProfileBuilder.clearLastResolvedForTest();
    // Avatar asks BotName.byEnvironment whether it is drawing the bot's face,
    // which reads Environment.appConfigOverride (GetStorage) then dotenv.
    // Unstubbed, the build throws and GetStorage's lazy init leaks a pending
    // timer into the test zone. Stubbed per test: flutter_test clears mock
    // method-call handlers between tests.
    final tempDir = await Directory.systemTemp.createTemp('creator_credit');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  QuestOutline outline(String? ownerId) => QuestOutline(
    quest: QuestPlan(
      id: 'quest-1',
      name: 'Plan it like a pro',
      description: 'Plan a trip.',
      targetLanguage: 'de',
      sequence: const [],
      ownerId: ownerId,
    ),
    groups: const [],
  );

  Future<QuestLoader> pumpRow(
    WidgetTester tester,
    AsyncState<QuestOutline> state,
  ) async {
    final loader = QuestLoader(state);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: Scaffold(body: CourseCreatorRow(questLoader: loader)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return loader;
  }

  testWidgets('credits the quest owner once the quest resolves', (
    tester,
  ) async {
    final loader = await pumpRow(tester, AsyncLoaded(outline(teacher)));
    addTearDown(loader.dispose);

    expect(find.text('Señora Díaz'), findsOneWidget);
    expect(find.text('PangeaChat'), findsNothing);
  });

  testWidgets('the credit is labelled, so it reads as attribution', (
    tester,
  ) async {
    final loader = await pumpRow(tester, AsyncLoaded(outline(teacher)));
    addTearDown(loader.dispose);

    expect(find.text('Created by'), findsOneWidget);
  });

  testWidgets('an uncredited course adds no stray label to the section', (
    tester,
  ) async {
    final loader = await pumpRow(tester, AsyncLoaded(outline(null)));
    addTearDown(loader.dispose);

    expect(find.text('Created by'), findsNothing);
  });

  testWidgets('credits PangeaChat for a system-owned course', (tester) async {
    final loader = await pumpRow(
      tester,
      AsyncLoaded(outline('@system:pangea.chat')),
    );
    addTearDown(loader.dispose);

    expect(find.text('PangeaChat'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('a quest with no owner recorded credits nobody', (tester) async {
    final loader = await pumpRow(tester, AsyncLoaded(outline(null)));
    addTearDown(loader.dispose);

    expect(find.byType(Text), findsNothing);
    expect(tester.getSize(find.byType(CourseCreatorRow)), Size.zero);
  });

  testWidgets('shows nothing while the quest is still loading', (tester) async {
    final loader = await pumpRow(tester, const AsyncLoading());
    addTearDown(loader.dispose);

    expect(find.byType(Text), findsNothing);
    expect(tester.getSize(find.byType(CourseCreatorRow)), Size.zero);
  });

  testWidgets('picks the credit up when the quest lands after first build', (
    tester,
  ) async {
    final loader = await pumpRow(tester, const AsyncLoading());
    addTearDown(loader.dispose);
    expect(find.text('Señora Díaz'), findsNothing);

    loader.value = AsyncLoaded(outline(teacher));
    await tester.pumpAndSettle();

    expect(find.text('Señora Díaz'), findsOneWidget);
  });
}
