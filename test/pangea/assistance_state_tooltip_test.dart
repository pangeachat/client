import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/assistance_state_enum.dart';

/// #8848 — the writing-assistance button's tooltip is also its accessible
/// name, so no state may leave it empty. The common states once evaluated the
/// string without returning it and fell through to "".
void main() {
  testWidgets('every assistance state names the button', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10n.of(context);

    for (final state in AssistanceStateEnum.values) {
      expect(state.tooltip(context), isNotEmpty, reason: '$state');
    }
    for (final state in [
      AssistanceStateEnum.notFetched,
      AssistanceStateEnum.igcComplete,
    ]) {
      expect(state.tooltip(context), l10n.check, reason: '$state');
    }
    // #8904 — the lightbulb offers a suggestion, not a check.
    for (final state in [
      AssistanceStateEnum.suggesting,
      AssistanceStateEnum.suggestionComplete,
    ]) {
      expect(state.icon, Icons.lightbulb_outline, reason: '$state');
      expect(
        state.tooltip(context),
        l10n.writingAssistanceSuggestion,
        reason: '$state',
      );
    }
    expect(AssistanceStateEnum.error.tooltip(context), l10n.viewError);
  });
}
