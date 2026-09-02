import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/l10n/l10n_en.dart';
import 'package:fluffychat/routes/world/right_panel/panel_card_with_header.dart';

/// #8729 — every workspace panel is ONE named semantic group, authored by the
/// panel dispatchers. Two guarantees here: every panel type resolves a
/// non-empty display name (the group label source), and the shared header
/// widget contributes no group of its own (it would nest a second group
/// inside every headered panel).
void main() {
  test('every panel type has a display name for its group label', () {
    final l10n = L10nEn();
    for (final type in PanelTypesEnum.values) {
      expect(
        type.displayName(l10n).trim(),
        isNotEmpty,
        reason:
            '${type.name} needs a name — the dispatchers label every '
            "panel's semantic group with it (#8729)",
      );
    }
  });

  testWidgets('the shared header widget authors no semantic group of its own', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: PanelCardWithHeader(
            title: 'Sample',
            icon: Icons.close,
            onLeading: () {},
            tooltip: 'Close sample',
            child: const Text('content'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = L10n.of(tester.element(find.byType(PanelCardWithHeader)));
    expect(
      find.bySemanticsLabel(l10n.pageLabel('Sample')),
      findsNothing,
      reason:
          'the dispatcher authors the one group per panel (#8729); a second '
          'group here nests a group inside a group on every headered panel',
    );
    expect(find.text('Sample'), findsOneWidget);
    semantics.dispose();
  });
}
