import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/features/subscription/widgets/paywall_card.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/unsubscribed_practice_page.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/message_unsubscribed_card.dart';

/// #7929 normalized every subscription gate on one look: a shimmer skeleton of
/// the content, half-opacity stars, and a GOLD call to action naming the
/// feature. The gold and the per-feature label are the point — sharing the
/// theme's primary made the gates read as ordinary controls, and one generic
/// "subscribe" message told the user nothing about what they'd just reached for.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  group('the unlock call to action', () {
    for (final brightness in Brightness.values) {
      testWidgets('is gold, never the theme primary — ${brightness.name}', (
        tester,
      ) async {
        await pump(
          tester,
          const UnlockButton(label: 'unlock'),
          brightness: brightness,
        );

        final context = tester.element(find.byType(UnlockButton));
        final gold = AppConfig.goldByTheme(context);

        expect(
          tester.widget<PressableButton>(find.byType(PressableButton)).color,
          gold,
        );
        expect(
          gold,
          isNot(Theme.of(context).colorScheme.primary),
          reason: 'the gate must not wear the same color as ordinary controls',
        );
      });
    }

    testWidgets('carries no stars unless asked', (tester) async {
      await pump(tester, const UnlockButton(label: 'unlock'));
      expect(find.byType(DecorativeStar), findsNothing);
    });

    testWidgets('draws its stars behind the label', (tester) async {
      await pump(tester, const UnlockButton(label: 'unlock', showStars: true));

      final stars = find.byType(DecorativeStar);
      expect(stars, findsNWidgets(2));

      final children = tester
          .widget<Stack>(
            find.ancestor(of: stars.first, matching: find.byType(Stack)).first,
          )
          .children;
      expect(
        children.indexWhere((child) => child is! Positioned),
        children.length - 1,
        reason:
            'both stars are Positioned and the pill is not, so the pill being '
            'the last child is what keeps the stars from eating its contrast',
      );
    });
  });

  group('decorative stars', () {
    testWidgets('are half opacity and never announced', (tester) async {
      await pump(
        tester,
        const Stack(
          children: [
            SizedBox(width: 200, height: 200),
            DecorativeStars(stars: [DecorativeStarSpec(size: 40, top: 0)]),
          ],
        ),
      );

      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(DecorativeStar),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        0.5,
      );
      expect(
        find.ancestor(
          of: find.text('⭐'),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
        reason: 'texture, not content — a screen reader must not read it out',
      );
    });
  });

  group('gated select modes', () {
    testWidgets('each pitch the feature the user reached for', (tester) async {
      await pump(tester, const SizedBox());
      final context = tester.element(find.byType(Scaffold));
      final l10n = L10n.of(context);

      expect(
        {for (final mode in SelectMode.values) mode: mode.unlockLabel(context)},
        {
          SelectMode.audio: l10n.unlockPremiumAudio,
          SelectMode.translate: l10n.unlockTranslations,
          SelectMode.speechTranslation: l10n.unlockTranslations,
          SelectMode.practice: l10n.unlockMessagePractice,
          SelectMode.emoji: l10n.unlockEmojiMode,
          // Regeneration is FREE — anyone may re-ask the bot. A null label is
          // how the gate learns not to fire, so this must stay null.
          SelectMode.requestRegenerate: null,
        },
      );
    });
  });

  group('the gated surfaces lay out', () {
    testWidgets('word card keeps its word, close, and gold CTA', (
      tester,
    ) async {
      await pump(
        tester,
        MessageUnsubscribedCard(
          token: PangeaTokenText.fromString('Deutsch'),
          onClose: () {},
        ),
      );

      final l10n = L10n.of(
        tester.element(find.byType(MessageUnsubscribedCard)),
      );
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(
        find.widgetWithText(UnlockButton, l10n.unlockLearningTools),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('writing-assistance card shows the skeleton, not a paragraph', (
      tester,
    ) async {
      await pump(tester, const PaywallCard());

      final l10n = L10n.of(tester.element(find.byType(PaywallCard)));
      expect(find.text(l10n.clickMessageTitle), findsOneWidget);
      expect(
        find.text(l10n.subscribedToUnlockTools),
        findsNothing,
        reason: 'the gate shows the feature now instead of describing it',
      );
      expect(
        find.widgetWithText(UnlockButton, l10n.unlockWritingAssistance),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('practice page keeps its stars and goes gold', (tester) async {
      await pump(tester, const UnsubscribedPracticePage());

      final l10n = L10n.of(
        tester.element(find.byType(UnsubscribedPracticePage)),
      );
      expect(find.byType(DecorativeStar), findsNWidgets(4));
      expect(
        find.widgetWithText(UnlockButton, l10n.unlockPracticeActivities),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
