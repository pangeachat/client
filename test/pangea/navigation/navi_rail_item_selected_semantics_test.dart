import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navi_rail_item.dart';
import '../../utils/test_client.dart';

/// #8743 (finding 13 of the 2026-09 a11y triage, #8689): the rail's active
/// section was conveyed by the visual highlight only — no rail item exposed a
/// selected state to assistive tech, so "All chats" announced identically
/// whether or not the chat list was open. The item's semantics must carry the
/// same [NaviRailItem.isSelected] that drives the highlight.
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

  Future<void> pumpRail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Provider<MatrixState>.value(
            value: _FakeMatrixState(client),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NaviRailItem(
                    toolTip: 'Active section',
                    isSelected: true,
                    onTap: () {},
                    icon: const Icon(Icons.forum_outlined),
                    naviRailWidth: 80,
                  ),
                  NaviRailItem(
                    toolTip: 'Inactive section',
                    isSelected: false,
                    onTap: () {},
                    icon: const Icon(Icons.map_outlined),
                    naviRailWidth: 80,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // L10n is deferred-loaded, so the subtree only builds once it resolves.
    await tester.pumpAndSettle();
  }

  testWidgets('the active rail item announces as selected and the inactive '
      'one as not selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRail(tester);

    expect(
      tester.getSemantics(find.byTooltip('Active section')),
      isSemantics(hasSelectedState: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byTooltip('Inactive section')),
      isSemantics(hasSelectedState: true, isSelected: false),
      reason:
          'an inactive item still exposes the selected state (as "not '
          'selected"), so the flag comes from isSelected, not a default',
    );

    handle.dispose();
  });
}
