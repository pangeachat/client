import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/close_button_labels.dart';

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
    'chats',
    'room',
    'session',
    'course',
    'coursepage',
    'addcourse',
    'analytics',
    'vocab',
    'grammar',
    'practice',
    'settings',
  ];

  testWidgets('every panel type gets a distinct, contextual close label', (
    tester,
  ) async {
    await captureL10n(tester);

    final labels = {
      for (final type in closeableTypes)
        type: closeButtonLabel(l10n, PanelToken(type)),
    };

    // None degrades to the bare "Close" the issue is about.
    for (final entry in labels.entries) {
      expect(
        entry.value,
        isNot(l10n.close),
        reason: '${entry.key} should carry a contextual close label, not "Close"',
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
      closeButtonLabel(l10n, const PanelToken('settingspage'), named: 'Learning'),
      l10n.closeNamed('Learning'),
    );
  });

  testWidgets('an unknown panel type falls back to the generic close', (
    tester,
  ) async {
    await captureL10n(tester);
    expect(closeButtonLabel(l10n, const PanelToken('mysterymeat')), l10n.close);
  });
}
