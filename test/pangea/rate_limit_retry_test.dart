import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/routes/onboarding/custom_course_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// A choreo 429 is transient — bounded by the limiter's 60s sliding window,
/// and observed in the wild at 2–35s — but the word card surfaced it as a red
/// error the moment it landed (#8794). `BaseRepo` now waits it out once for
/// the repos that opt in, so the card stays on its shimmer instead.
///
/// These drive the real singletons through a `MockClient` installed for the
/// zone, so `Requests` runs for real and the assertions are about the contract
/// callers see rather than a stubbed fetch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('rate_limit_retry');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    await GetStorage.init('lemma_storage');
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'syt_test_token',
    );
  });

  setUp(() {
    dotenv.testLoad(mergeWith: {'CHOREO_API': choreoApi});
    RateLimitPause.choreo.reset();
    RateLimitPause.subscription.reset();
    // The wait is wall-clock; nothing here is asserting its length.
    BaseRepo.rateLimitRetryWait = Duration.zero;
  });

  tearDown(() {
    RateLimitPause.choreo.reset();
    RateLimitPause.subscription.reset();
    BaseRepo.rateLimitRetryWait = const Duration(seconds: 5);
  });

  /// A distinct lemma per call, so neither the disk cache nor the in-flight
  /// dedupe hands one test the previous test's answer.
  var seq = 0;
  LemmaInfoRequest lemmaRequest() => LemmaInfoRequest(
    lemma: 'palabra${seq++}',
    partOfSpeech: 'noun',
    lemmaLang: 'es',
    userL1: 'en',
    messageInfo: const {},
  );

  // `http.Response`'s string constructor encodes latin1 unless the charset
  // says otherwise, and the repo reads `bodyBytes` as utf-8 — so a body with
  // an emoji in it needs the same content type the real server sends.
  const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  Response ok(BaseRequest request) => Response(
    jsonEncode({
      'emoji': ['🙂'],
      'meaning': 'a word',
    }),
    200,
    request: request,
    headers: jsonHeaders,
  );

  Response tooMany(BaseRequest request) => Response(
    jsonEncode({'detail': 'Rate limit exceeded. Please slow down.'}),
    429,
    request: request,
    headers: jsonHeaders,
  );

  group('a repo that opts into the rate-limit retry', () {
    test('waits out a 429 and returns the retry, not the throttle', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((request) async {
          calls++;
          return calls == 1 ? tooMany(request) : ok(request);
        }),
      );

      expect(calls, 2, reason: 'the 429 should have been retried exactly once');
      expect(result.isError, isFalse);
      expect(result.asValue!.value.meaning, 'a word');
    });

    test('surfaces the error when the retry is throttled too', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((request) async {
          calls++;
          return tooMany(request);
        }),
      );

      // Bounded: one retry, then the real error — never a loop, and never a
      // card that shimmers forever (#8794 "still error out ...").
      expect(calls, 2);
      expect(result.isError, isTrue);
      expect(PangeaHttpException.statusCodeOf(result.asError!.error), 429);
    });

    test('does not retry a failure that is not a throttle', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((request) async {
          calls++;
          return Response('', 500, request: request);
        }),
      );

      expect(calls, 1);
      expect(result.isError, isTrue);
    });

    test(
      'concurrent callers join the retry, not the throttled attempt',
      () async {
        var calls = 0;
        final request = lemmaRequest();
        // Same storage key, so the second call lands on the in-flight entry. If
        // that entry were the first ATTEMPT rather than the retrying operation,
        // this caller would be handed the 429 the attempt it joined returned.
        final results = await runWithClient(() {
          final first = LemmaInfoRepo.instance.get(request);
          final second = LemmaInfoRepo.instance.get(request);
          return Future.wait([first, second]);
        }, () => MockClient((r) async => ++calls == 1 ? tooMany(r) : ok(r)));

        expect(
          calls,
          2,
          reason: 'the two callers share one fetch and one retry',
        );
        expect(results.every((r) => !r.isError), isTrue);
      },
    );
  });

  group('the shared budget', () {
    test('is armed by a 429 from a repo that does not itself retry', () async {
      expect(RateLimitPause.choreo.isPaused, isFalse);

      await runWithClient(
        () => CustomCourseRepo.instance.get(
          CustomCourseRequestModel(
            name: 'Course ${seq++}',
            languagePair: 'en-es',
            languageLevel: LanguageLevelTypeEnum.a1,
            institution: 'Test School',
            goals: 'Order coffee in Spanish',
          ),
        ),
        () => MockClient((request) async => tooMany(request)),
      );

      // The point of the consolidation: a 429 anywhere on `/choreo` pauses the
      // budget for everything on it, because the read that sees the 429 is
      // rarely the read that spent it.
      expect(RateLimitPause.choreo.isPaused, isTrue);
      expect(RateLimitPause.subscription.isPaused, isFalse);
    });

    test('is not armed by a failure that is not a throttle', () async {
      await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () =>
            MockClient((request) async => Response('', 503, request: request)),
      );

      expect(RateLimitPause.choreo.isPaused, isFalse);
    });

    test('routes a failure to the budget its path names', () {
      RateLimitPause? pauseFor(String path) => RateLimitPause.forError(
        PangeaHttpException(
          statusCode: 429,
          method: 'POST',
          path: path,
          detail: 'Rate limit exceeded. Please slow down.',
        ),
      );

      // Mirrors the server's `_scope_for`. An AI 429 must never pause
      // checkout, which is the whole reason these are two instances.
      expect(pauseFor('/choreo/lemma_definition'), same(RateLimitPause.choreo));
      expect(
        pauseFor('/subscription/checkout'),
        same(RateLimitPause.subscription),
      );
      expect(pauseFor('/subscription'), same(RateLimitPause.subscription));
      // Hosts choreo's limiter does not meter.
      expect(pauseFor('/cms/api/languages'), isNull);
      expect(pauseFor('/api/internal/analytics-events'), isNull);
    });
  });
}
