import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_course_details_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

/// #8322 — a stale or hand-edited `?c=` (e.g. `?c=!fakecourseId&left=course`)
/// names a course the client cannot resolve, so the course card falls to its
/// "oops, something went wrong" state. That state used to render a bare app bar
/// with no leading control, stranding the learner on a panel they could not
/// close. It now carries the panel's injected close control, the same fix
/// [LeftPanelRoomSubpage] got in #7746.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
  });

  tearDownAll(() => client.dispose());

  testWidgets('an unresolvable course id renders the panel close control', (
    tester,
  ) async {
    const closeKey = Key('the-close-button');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: const LeftPanelCourseDetailsSubpage(
            param: null,
            spaceId: '!fakecourseId:fakeserver.notexisting',
            closeButton: IconButton(
              key: closeKey,
              icon: Icon(Icons.close),
              onPressed: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(closeKey), findsOneWidget);
  });
}
