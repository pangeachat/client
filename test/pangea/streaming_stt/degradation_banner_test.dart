import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/degradation_banner.dart';

/// Pure widget-rendering tests for [DegradationBanner]: given a
/// [DegradationBannerKind] it must show the right one-line editorial copy and
/// an X that invokes [DegradationBanner.onDismiss] exactly once per tap —
/// independent of [RecordingViewModelState]. The wiring that DECIDES which
/// kind applies (provider-frame degrade, all-providers-down batch degrade,
/// gate-rejected language) is covered by the integration tests in
/// recording_view_model_streaming_test.dart / recording_view_model_batch_test.dart.
void main() {
  Future<void> pumpBanner(
    WidgetTester tester,
    DegradationBannerKind kind, {
    required VoidCallback onDismiss,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: DegradationBanner(kind: kind, onDismiss: onDismiss),
        ),
      ),
    );
  }

  testWidgets('kind.none renders no icon and no message', (tester) async {
    await pumpBanner(tester, DegradationBannerKind.none, onDismiss: () {});
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(DegradationBanner),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(DegradationBanner),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('degradedLive renders its exact editorial copy', (tester) async {
    await pumpBanner(
      tester,
      DegradationBannerKind.degradedLive,
      onDismiss: () {},
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Live transcription is running on a backup service. Quality may '
        'vary, please check the text.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('degradedToBatch renders its exact editorial copy', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      DegradationBannerKind.degradedToBatch,
      onDismiss: () {},
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Live transcription is unavailable right now. Your message was '
        "transcribed the standard way, without live editing. We're working "
        'to restore it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('languageUnsupported renders its exact editorial copy', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      DegradationBannerKind.languageUnsupported,
      onDismiss: () {},
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Live transcription isn't available for this language yet. We're "
        'working on it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the X invokes onDismiss exactly once', (tester) async {
    var dismissCount = 0;
    await pumpBanner(
      tester,
      DegradationBannerKind.degradedLive,
      onDismiss: () => dismissCount++,
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissCount, 1);
  });
}
