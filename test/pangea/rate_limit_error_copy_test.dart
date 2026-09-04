import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';

/// #8705 — right after login or a language change the client's own hydration
/// burst can spend the choreo rate budget, so the next user action (word
/// card, activity open) fails with a 429. Every surface used to show its own
/// failure copy ("check your connection", "oops, something went wrong"),
/// which misdirects: waiting under a minute is the whole remedy. A throttled
/// failure must show the shared "wait a moment and try again" copy instead,
/// on every display path — `ErrorIndicator`, `CardErrorWidget`, `ErrorCopy`
/// (the writing-assistance bar), and `toLocalizedString` (the FluffyChat-wide
/// mapper the course plan renders through).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n enL10n;

  setUpAll(() async {
    // Loading a translation is real async work (deferred libraries), so it
    // can't happen inside a test body's fake clock — resolve it up front.
    enL10n = await lookupL10n(const Locale('en'));
  });

  PangeaHttpException http(int status) =>
      PangeaHttpException(statusCode: status, method: 'GET', path: '/choreo');

  group('RateLimitPause.isRateLimited', () {
    test('true for a 429 and for a suppressed read', () {
      expect(RateLimitPause.isRateLimited(http(429)), isTrue);
      expect(RateLimitPause.isRateLimited(RateLimitedException()), isTrue);
    });

    test('false for anything that is not backpressure', () {
      expect(RateLimitPause.isRateLimited(null), isFalse);
      expect(RateLimitPause.isRateLimited(http(404)), isFalse);
      expect(RateLimitPause.isRateLimited(http(500)), isFalse);
      expect(RateLimitPause.isRateLimited(TimeoutException('t')), isFalse);
      expect(RateLimitPause.isRateLimited(Exception('boom')), isFalse);
    });
  });

  Future<BuildContext> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    // The localization delegate resolves asynchronously, so the subtree is
    // empty on the first frame (the `en` translation itself is preloaded in
    // `setUpAll` — real async a test body's fake clock never gets to).
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    return tester.element(find.byWidget(child));
  }

  group('ErrorIndicator', () {
    testWidgets('a throttled failure shows the wait-and-retry copy', (
      tester,
    ) async {
      await pump(
        tester,
        ErrorIndicator(message: 'surface copy', error: http(429)),
      );
      expect(
        find.textContaining(enL10n.errorRateLimited, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('surface copy', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('any other failure keeps the surface\'s own copy', (
      tester,
    ) async {
      await pump(
        tester,
        ErrorIndicator(message: 'surface copy', error: http(500)),
      );
      expect(
        find.textContaining('surface copy', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('no error passed keeps the surface\'s own copy', (
      tester,
    ) async {
      await pump(tester, const ErrorIndicator(message: 'surface copy'));
      expect(
        find.textContaining('surface copy', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('rateLimitAwareCopy', () {
    // The shared selector behind `ErrorIndicator.error` and
    // `CardErrorWidget.cause` (the latter can't be pumped here — its BotFace
    // needs Rive's native library).
    testWidgets('replaces the fallback only for a throttle', (tester) async {
      final context = await pump(tester, const SizedBox.shrink());
      expect(
        rateLimitAwareCopy(context, http(429), 'surface copy'),
        enL10n.errorRateLimited,
      );
      expect(
        rateLimitAwareCopy(context, RateLimitedException(), 'surface copy'),
        enL10n.errorRateLimited,
      );
      expect(
        rateLimitAwareCopy(context, http(500), 'surface copy'),
        'surface copy',
      );
      expect(rateLimitAwareCopy(context, null, 'surface copy'), 'surface copy');
    });
  });

  group('error → copy mappers', () {
    testWidgets('ErrorCopy maps a 429 to the wait-and-retry copy', (
      tester,
    ) async {
      final context = await pump(tester, const SizedBox.shrink());
      expect(
        ErrorCopy(http(429)).toLocalizedString(context),
        enL10n.errorRateLimited,
      );
      // The generic default is untouched for other failures.
      expect(
        ErrorCopy(Exception('boom')).toLocalizedString(context),
        enL10n.errorTryAgainLater,
      );
    });

    testWidgets(
      'toLocalizedString maps a throttle to the wait-and-retry copy',
      (tester) async {
        final context = await pump(tester, const SizedBox.shrink());
        expect(http(429).toLocalizedString(context), enL10n.errorRateLimited);
        expect(
          RateLimitedException().toLocalizedString(context),
          enL10n.errorRateLimited,
        );
        // Anything else still falls through to the generic copy.
        expect(
          http(500).toLocalizedString(context),
          enL10n.oopsSomethingWentWrong,
        );
      },
    );
  });
}
