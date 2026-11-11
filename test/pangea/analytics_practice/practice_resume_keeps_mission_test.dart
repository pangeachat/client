import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import '../get_test_client.dart';

/// The view model only reads [updateDispatcher] off the analytics service.
class _FakeAnalyticsService implements AnalyticsDataService {
  @override
  late final AnalyticsUpdateDispatcher updateDispatcher =
      AnalyticsUpdateDispatcher(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A Mission's vocab session whose clock has started, so the tracker shows
/// its timer and a tap there resumes it.
PracticeSessionState _liveMissionSession() {
  final state = PracticeSessionHolder.instance.claim(
    ConstructTypeEnum.vocab,
    missionId: 'lo-1',
  );
  state.sessionController.session = AnalyticsPracticeSessionModel(
    startedAt: DateTime.now().subtract(const Duration(seconds: 90)),
    type: ConstructTypeEnum.vocab,
    practiceTargets: [
      AnalyticsPracticeTarget(
        target: PracticeTarget(
          tokens: [
            PangeaToken(
              text: PangeaTokenText.fromJson({'content': 'gato', 'offset': 0}),
              lemma: Lemma(text: 'gato', saveVocab: true, form: 'gato'),
              pos: 'NOUN',
              morph: const {},
            ),
          ],
          exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
        ),
      ),
    ],
    userL1: 'en',
    userL2: 'es',
  );
  return state;
}

/// Taps a button on a one-page workspace that runs [onTap] with the page's
/// context, and returns the router so the test can read the URL back.
Future<GoRouter> _tapInWorkspace(
  WidgetTester tester,
  void Function(BuildContext context) onTap,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => onTap(context),
            child: const Text('tap'),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('tap'));
  await tester.pumpAndSettle();
  return router;
}

/// The practice panel claims the session its URL token names, so the resume
/// has to name the live session, Mission included, or the claim replaces it.
void _expectResumes(GoRouter router, PracticeSessionState live) {
  final param = parseOpenPanels(
    router.routeInformationProvider.value.uri,
  ).right.whereType<AnalyticsPracticePanelToken>().single.param!;
  final holder = PracticeSessionHolder.instance;
  final claimed = holder.claim(param.constructType, missionId: param.missionId);
  // Before asserting: ending cancels the idle watchdog the claim armed, which
  // the test's fake clock would otherwise report as a pending timer.
  holder.end();

  expect(param.missionId, live.missionId);
  expect(claimed, same(live));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late WorldUserClusterViewModel viewModel;

  setUpAll(() async {
    // The view model reaches ActivityPlanRepo, whose cache opens GetStorage.
    final tempDir = await Directory.systemTemp.createTemp('practice_resume');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    client = await getTestClient();
    viewModel = WorldUserClusterViewModel(
      analyticsService: _FakeAnalyticsService(),
      client: client,
    );
  });

  tearDownAll(() async {
    viewModel.dispose();
    await client.dispose();
  });

  setUp(PracticeSessionHolder.instance.end);

  // routing.instructions.md § Practice is a persistent background session:
  // during practice the tracker resumes it instead of opening analytics.
  testWidgets('the tracker resumes a Mission session with its Mission', (
    tester,
  ) async {
    final live = _liveMissionSession();

    final router = await _tapInWorkspace(
      tester,
      (context) => viewModel.openAnalytics(context, AnalyticsPanelTab.vocab),
    );

    _expectResumes(router, live);
  });

  testWidgets('a vocab tap resumes a Mission session with its Mission', (
    tester,
  ) async {
    final live = _liveMissionSession();

    final router = await _tapInWorkspace(
      tester,
      (context) => AnalyticsNavigationUtil.navigateToAnalytics(
        context: context,
        view: ProgressIndicatorEnum.wordsUsed,
      ),
    );

    _expectResumes(router, live);
  });
}
