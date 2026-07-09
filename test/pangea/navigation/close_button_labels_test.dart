import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// Regression coverage for #7274 ("[SR] duplicate close button confusion"):
/// several panels can be open at once, each with its own close (X). A bare
/// "Close" is indistinguishable to a screen reader, so every panel type must
/// yield its own contextual close label.
void main() {
  late L10n l10n;

  Future<void> captureL10n(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Every panel type whose close control routes through [closeButtonLabel].
  const closeableTypes = [
    PanelTypesEnum.chats,
    PanelTypesEnum.room,
    PanelTypesEnum.session,
    PanelTypesEnum.course,
    PanelTypesEnum.coursepage,
    PanelTypesEnum.addcourse,
    PanelTypesEnum.addcoursepage,
    PanelTypesEnum.analytics,
    PanelTypesEnum.vocab,
    PanelTypesEnum.grammar,
    PanelTypesEnum.practice,
    PanelTypesEnum.settings,
  ];

  testWidgets('every panel type gets a distinct, contextual close label', (
    tester,
  ) async {
    await captureL10n(tester);

    final labels = {
      for (final type in closeableTypes) type: type.closeButtonLabel(l10n),
    };

    // None degrades to the bare "Close" the issue is about.
    for (final entry in labels.entries) {
      expect(
        entry.value,
        isNot(l10n.close),
        reason:
            '${entry.key} should carry a contextual close label, not "Close"',
      );
    }

    // All distinct — so coexisting close buttons are distinguishable by name.
    expect(
      labels.values.toSet().length,
      labels.length,
      reason: 'close labels must be unique per panel type: $labels',
    );
  });

  testWidgets('a dynamic title (named) overrides the per-type label', (
    tester,
  ) async {
    await captureL10n(tester);
    expect(
      PanelTypesEnum.settingspage.closeButtonLabel(l10n, named: 'Learning'),
      l10n.closeNamed('Learning'),
    );
  });
}
