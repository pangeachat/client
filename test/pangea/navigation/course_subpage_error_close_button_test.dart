import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_details_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

/// #8327 — a `coursepage:<page>` panel reads its space id from `?c=`, and
/// [LeftPanelRoomDetailsSubpage] hands it straight to the page with no
/// room-existence gate of its own. A stale or hand-edited id (e.g.
/// `?c=!fakecourseId&left=coursepage:invite`) therefore reaches the page's own
/// "oops, something went wrong" state, which used to render a bare app bar with
/// no leading control — stranding the learner on a panel they could not close.
/// Each error state now carries the panel's injected close control, the same
/// fix the course card got in #8322 and [LeftPanelRoomSubpage] in #7746.
///
/// The `room:<id>/...` path needs no equivalent test: [LeftPanelRoomSubpage]
/// intercepts an unresolvable room with its own #7746 empty state before any
/// of these pages build.
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

  for (final subpage in [RoomSubpageEnum.invite, RoomSubpageEnum.emotes]) {
    testWidgets(
      'an unresolvable course id on ${subpage.name} renders the panel close control',
      (tester) async {
        const closeKey = Key('the-close-button');

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Provider<MatrixState>.value(
              value: _FakeMatrixState(client),
              child: LeftPanelRoomDetailsSubpage(
                roomId: '!fakecourseId:fakeserver.notexisting',
                param: RoomSubpageTokenParam(subpage: subpage),
                closeButton: const IconButton(
                  key: closeKey,
                  icon: Icon(Icons.close),
                  onPressed: null,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Read the localized string from the live element tree rather than
        // awaiting L10n.delegate.load — awaiting that future stalls the
        // testWidgets fake-async clock.
        final l10n = L10n.of(
          tester.element(find.byType(LeftPanelRoomDetailsSubpage)),
        );
        expect(find.text(l10n.oopsSomethingWentWrong), findsOneWidget);
        expect(find.byKey(closeKey), findsOneWidget);
      },
    );
  }
}
