import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// What a report's `m` description reaches Sentry as — asserted on the event
/// the sink actually produces, because the whole failure mode being pinned here
/// is a message that went somewhere other than the event.
///
/// `m` has been wrong in both directions. It was silently dropped whenever `e`
/// was non-null — `captureException(e ?? Exception(m))` only ever read it in
/// the no-exception case — so 37 sites passed a hand-written message that
/// reached `debugPrint` and nothing else, and searching Sentry for one of our
/// own strings returned nothing (#8660). Removing it then cost the other half:
/// with `e` required, a failure that carries no exception of its own could not
/// be reported at all without inventing one at the call site.
///
/// So the contract is both halves at once, and both are pinned below: `m` alone
/// IS the event, and `m` beside an `e` is still ON the event. A report is never
/// a message that only a developer with a debug console attached can read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();

  setUp(() async {
    ErrorHandler.resetReportedOnceKeysForTest();
    await harness.init();
  });

  tearDown(() => harness.close());

  /// The single event [report] produces.
  Future<SentryEvent> eventOf(void Function() report) =>
      harness.capture(report);

  /// The `m` description carried by [event], wherever the sink put it: the
  /// title when nothing else owns it, the [ErrorHandler.messageContext] context
  /// when an exception does. A message in neither place is a dropped message,
  /// which is the defect.
  String? messageOf(SentryEvent event) {
    final context = event.contexts[ErrorHandler.messageContext];
    if (context is Map && context['value'] is String) {
      return context['value'] as String;
    }
    return event.throwable?.toString();
  }

  PangeaHttpException http(int status) => PangeaHttpException.fromResponse(
    Response(
      '',
      status,
      request: Request('GET', Uri.parse('https://api.pangea.chat/x')),
    ),
  );

  /// The real one, from `CallTokenRepo._reportMissingMetadataGrant`: a token
  /// minted without a claim it was supposed to carry. Nothing threw — the state
  /// is simply wrong — so there is no exception to attach and never was.
  const missingGrant =
      'The call token carries no pangea_own_metadata grant; this '
      "account's devices cannot tell each other what they are recording";

  group('a failure carrying no exception', () {
    test(
      'still reaches Sentry, rather than being dropped at the sink',
      () async {
        final event = await eventOf(
          () => ErrorHandler.logError(m: missingGrant, data: {}),
        );
        expect(event, isNotNull);
      },
    );

    test('arrives with its message as the title, not as "null"', () async {
      final event = await eventOf(
        () => ErrorHandler.logError(m: missingGrant, data: {}),
      );
      // The #8660 acceptance criterion, in the one direction that survived:
      // searching Sentry for a string we wrote finds the event.
      expect(event.throwable.toString(), contains(missingGrant));
    });

    test(
      'is an error by the severity table, having no status to soften it',
      () async {
        final event = await eventOf(
          () => ErrorHandler.logError(m: missingGrant, data: {}),
        );
        expect(event.level, SentryLevel.error);
      },
    );

    test(
      'reports through logErrorOnce, which no longer requires an e',
      () async {
        late final Future<bool> reporting;
        final event = await eventOf(() {
          reporting = ErrorHandler.logErrorOnce(
            key: 'call-token-missing-metadata-grant',
            m: missingGrant,
            data: {'videoGrantClaims': <String>[]},
          );
        });
        // The return value, not merely that the call was made: logErrorOnce
        // answers whether THIS call reported, and a no-exception report that
        // silently returned false would spend the key without raising anything.
        expect(await reporting, isTrue);
        expect(messageOf(event), contains(missingGrant));
      },
    );

    test('with neither e nor m still produces an event, not a crash', () async {
      final event = await eventOf(() => ErrorHandler.logError(data: {}));
      expect(event.throwable.toString(), contains('no message supplied'));
    });
  });

  group('a message alongside an exception', () {
    /// The roster's real pair: a caught write failure, plus the sentence saying
    /// what the failure costs. Before #8660 this sentence reached `debugPrint`
    /// and nothing else.
    const rosterMessage =
        "This device could not tell the account's other devices what it can "
        'do or is doing';

    test('is not dropped — it reaches the event', () async {
      final event = await eventOf(
        () => ErrorHandler.logError(
          e: Exception('m.room.member write rejected'),
          m: rosterMessage,
          data: {},
        ),
      );
      expect(messageOf(event), rosterMessage);
    });

    test('leaves the caught exception owning the title', () async {
      final failure = Exception('m.room.member write rejected');
      final event = await eventOf(
        () => ErrorHandler.logError(e: failure, m: rosterMessage, data: {}),
      );
      // #8660 removed the messages rather than folding them into `e` precisely
      // because wrapping changes the runtime type that severityOf and
      // fingerprintOf both read. The message rides beside the exception; it
      // must never replace or wrap it.
      expect(event.throwable, same(failure));
    });

    test('does not disturb the severity the exception is owed', () async {
      final event = await eventOf(
        () => ErrorHandler.logError(e: http(404), m: rosterMessage, data: {}),
      );
      // Named in the reason because two SentryLevels both render as
      // "Instance of 'SentryLevel'" in a failure, which says nothing about
      // which way the table went.
      expect(
        event.level,
        SentryLevel.warning,
        reason: 'a 404 is a warning; got ${event.level?.name}',
      );
    });

    test('does not disturb the grouping the exception is owed', () async {
      final event = await eventOf(
        () => ErrorHandler.logError(e: http(503), m: rosterMessage, data: {}),
      );
      expect(event.fingerprint, ['pangea-http', '503', 'GET', '/x']);
    });
  });

  group('a report with no message', () {
    test('sets no message context — existing callers are untouched', () async {
      final event = await eventOf(
        () => ErrorHandler.logError(e: Exception('parse'), data: {}),
      );
      expect(event.contexts[ErrorHandler.messageContext], isNull);
    });
  });

  group('ErrorHandler.shouldReport', () {
    test('reports a null exception rather than suppressing it', () {
      // shouldReport exists to suppress exactly one control-flow type. A null
      // is not that type — it is the no-exception failure the nullable `e`
      // exists to raise, so suppressing it here would silently drop precisely
      // the alarm, which is the #8660 defect wearing a different hat.
      expect(ErrorHandler.shouldReport(null), isTrue);
    });
  });
}
