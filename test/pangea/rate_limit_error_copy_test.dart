import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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
  _retryAfterTests();
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

/// `Retry-After` parsing. The header is the server telling us exactly when its
/// window frees up; misreading it is worse than ignoring it, so anything that
/// is not a plain non-negative second count is treated as "no advice given"
/// and the caller falls back to its own default.
void _retryAfterTests() {
  http.Response respond(Map<String, String> headers) => http.Response(
    '{}',
    429,
    headers: headers,
    request: http.Request('GET', Uri.parse('https://x/y')),
  );

  group('Retry-After', () {
    test('a delta-seconds value is read', () {
      expect(
        PangeaHttpException.retryAfterFromResponse(
          respond({'retry-after': '42'}),
        ),
        const Duration(seconds: 42),
      );
    });

    test('surrounding whitespace does not defeat it', () {
      expect(
        PangeaHttpException.retryAfterFromResponse(
          respond({'retry-after': ' 7 '}),
        ),
        const Duration(seconds: 7),
      );
    });

    test('an absent header is no advice, not zero', () {
      // Zero would mean "retry immediately", the opposite of what silence means.
      expect(PangeaHttpException.retryAfterFromResponse(respond({})), isNull);
    });

    test('an HTTP-date value is declined rather than guessed at', () {
      // Legal HTTP, but we never send it, and a client clock that disagrees
      // with the server's would turn it into an arbitrary wait.
      expect(
        PangeaHttpException.retryAfterFromResponse(
          respond({'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'}),
        ),
        isNull,
      );
    });

    test('a negative value is declined', () {
      expect(
        PangeaHttpException.retryAfterFromResponse(
          respond({'retry-after': '-5'}),
        ),
        isNull,
      );
    });

    test('a streamed response keeps its headers', () {
      // `http.Response.bytes` defaults headers to empty, so materializing a
      // streamed 429 without passing them silently drops the one header the
      // caller needs and sends it back to guessing.
      final request = http.Request('GET', Uri.parse('https://x/y'));
      final streamed = http.StreamedResponse(
        const Stream<List<int>>.empty(),
        429,
        headers: {'retry-after': '12'},
      );
      final e = PangeaHttpException.fromStreamedResponse(
        request,
        streamed,
        <int>[],
      );
      expect(e.retryAfter, const Duration(seconds: 12));
    });

    test('it rides on the typed exception for callers to read', () {
      final e = PangeaHttpException.fromResponse(
        respond({'retry-after': '15'}),
      );
      expect(e.retryAfter, const Duration(seconds: 15));
      expect(PangeaHttpException.retryAfterOf(e), const Duration(seconds: 15));
      expect(PangeaHttpException.retryAfterOf(Exception('other')), isNull);
    });
  });
}
