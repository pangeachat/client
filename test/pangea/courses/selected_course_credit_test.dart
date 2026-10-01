import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/content_creator_chip.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/routes/courses/own/selected_course_view.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

/// The create-course page is the ONE course surface where the credit is
/// prominent: a teacher deciding whether to build their class on someone
/// else's plan is deciding partly on who made it. After the space exists the
/// same credit moves to the course page's More section, where it is a detail
/// rather than a banner over the teacher's own description (#8819).
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const teacher = '@christiane:pangea.chat';

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    await client.database.storeUserProfile(
      teacher,
      CachedProfileInformation.fromProfile(
        ProfileInformation(displayname: 'Christiane Reves'),
        outdated: false,
        updated: DateTime.now(),
      ),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(() async {
    UserProfileBuilder.clearLastResolvedForTest();
    // Avatar reads BotName.byEnvironment (GetStorage, then dotenv); unstubbed
    // it throws and leaks a pending timer into the test zone.
    final tempDir = await Directory.systemTemp.createTemp('course_credit');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  CoursePlanModel plan(String? ownerId) => CoursePlanModel(
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
    ownerId: ownerId,
  );

  Future<void> pumpView(WidgetTester tester, {required String? ownerId}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: SelectedCourseView(
            title: 'New course',
            course: plan(ownerId),
            // The course card is exercised by its own tests; leaving it out
            // keeps this one about the credit.
            content: null,
            onTapCta: () {},
            ctaButtonText: 'Create course',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('credits whoever built the plan, beside the create button', (
    tester,
  ) async {
    await pumpView(tester, ownerId: teacher);

    expect(find.text('Created by'), findsOneWidget);
    expect(find.text('Christiane Reves'), findsOneWidget);
    expect(
      find.text('PangeaChat'),
      findsNothing,
      reason: "a teacher's course plan is never credited to Pangea",
    );
  });

  testWidgets('the credit is prominent here, larger than the detail form', (
    tester,
  ) async {
    await pumpView(tester, ownerId: teacher);

    expect(
      tester
          .widget<ContentCreatorCredit>(find.byType(ContentCreatorCredit))
          .avatarSize,
      ContentCreatorCredit.prominentAvatarSize,
    );
  });

  testWidgets('a Pangea catalog plan says so', (tester) async {
    await pumpView(tester, ownerId: ContentCreatorChip.systemOwnerId);

    expect(find.text('PangeaChat'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('a plan with no owner recorded credits nobody', (tester) async {
    await pumpView(tester, ownerId: null);

    expect(find.byType(ContentCreatorCredit), findsNothing);
    expect(find.text('Created by'), findsNothing);
    expect(find.text('PangeaChat'), findsNothing);
  });
}
