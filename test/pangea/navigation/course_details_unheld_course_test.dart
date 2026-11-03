import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_course_details_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';
import '../get_test_client.dart';

/// #9586 — a `course` token naming a course the learner is not in (a
/// join-course notice's path, a stale or hand-edited `?c=`) has no card to
/// render. Once the room list is complete, the token is replaced in place by
/// the course's preview, where the learner can join. Until then the panel
/// shows its loading state with the injected close control, so the learner
/// is never stranded on a panel they cannot close (#8322).
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

// Bare: no home domain is set in a widget test, so the id rides as typed.
const _courseId = '!notheld';
const _closeKey = Key('the-close-button');

GoRouter _router(MatrixState matrixState) => GoRouter(
  initialLocation: '/?c=!notheld&left=course',
  routes: [
    GoRoute(
      path: '/',
      // Like the shell: the course panel renders only while `?c=` names it.
      builder: (context, state) => activeSpaceIdFor(state.uri) == null
          ? const SizedBox.shrink()
          : Provider<MatrixState>.value(
              value: matrixState,
              child: LeftPanelCourseDetailsSubpage(
                param: null,
                spaceId: activeSpaceIdFor(state.uri),
                closeButton: const IconButton(
                  key: _closeKey,
                  icon: Icon(Icons.close),
                  onPressed: null,
                ),
              ),
            ),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, GoRouter router) => tester.pumpWidget(
  MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
  ),
);

void main() {
  late Client syncedClient;
  late Client freshClient;

  // Built outside the widget tests: the store's real I/O never completes
  // inside their fake-async zone.
  setUpAll(() async {
    syncedClient = await getTestClient();
    freshClient = await prepareTestClient();
  });

  tearDownAll(() async {
    await syncedClient.dispose();
    await freshClient.dispose();
  });

  testWidgets('a course not in the complete room list opens its preview', (
    tester,
  ) async {
    // Logged in and past its first sync, so the room list is the answer.
    expect(syncedClient.prevBatch, isNotNull);
    expect(syncedClient.getRoomById(_courseId), isNull);

    final router = _router(_FakeMatrixState(syncedClient));
    // The panel awaits the client's room-list future, which completes on the
    // real event loop, never inside the fake-async zone.
    await tester.runAsync(() async {
      await _pump(tester, router);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    // A spinner never settles: a replace that did not land fails here fast.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(activeSpaceIdFor(uri), isNull);
    expect(
      parseOpenPanels(uri).left.last,
      isA<AddCoursePagePanelToken>().having(
        (t) => t.param?.previewRoomId,
        'previewRoomId',
        _courseId,
      ),
    );
  });

  testWidgets('before the first sync the panel waits, and can be closed', (
    tester,
  ) async {
    expect(freshClient.prevBatch, isNull);

    final router = _router(_FakeMatrixState(freshClient));
    await _pump(tester, router);
    // Not pumpAndSettle: the loading spinner never settles.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(_closeKey), findsOneWidget);
    expect(
      activeSpaceIdFor(router.routerDelegate.currentConfiguration.uri),
      _courseId,
    );
  });
}
