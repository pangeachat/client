import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_cta_row.dart';
import 'package:fluffychat/routes/courses/own/selected_course_view.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// Start my own's course-to-join preview offers "Create my own course" under
/// Join (#9590). The minimized sheet rest has to hold both.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    final tempDir = await Directory.systemTemp.createTemp('create_own');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  tearDownAll(() => client.dispose());

  final plan = CoursePlanModel(
    uuid: 'quest-1',
    title: 'Spanish 101: Everyday Spanish, from Class to Home',
    description: 'First conversations.',
    targetLanguage: 'es',
    languageOfInstructions: 'en',
    cefrLevel: LanguageLevelTypeEnum.a1,
    topicIds: const [],
    mediaIds: const [],
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // The shell's minimized course-preview rest (_coursePreviewSheetMinimizedHeight).
  const minimizedRest = 188.0;

  Future<void> pumpView(
    WidgetTester tester, {
    required double height,
    CourseCtaAction? alternative,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 375,
              height: height,
              child: SelectedCourseView(
                title: 'Join',
                course: plan,
                content: CoursePlanAddCourseTileContent(plan),
                onTapCta: () {},
                ctaButtonText: 'Join',
                ctaAlternative: alternative,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the minimized rest holds Join and the create action', (
    tester,
  ) async {
    var created = false;
    await pumpView(
      tester,
      height: minimizedRest,
      alternative: CourseCtaAction(
        label: 'Create my own course',
        onPressed: () => created = true,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Join'), findsOneWidget);
    await tester.tap(find.text('Create my own course'));
    expect(created, isTrue);
  });

  testWidgets('without it, the preview shows Join alone', (tester) async {
    await pumpView(tester, height: 600);

    expect(find.text('Join'), findsOneWidget);
    expect(find.text('Create my own course'), findsNothing);
  });
}
