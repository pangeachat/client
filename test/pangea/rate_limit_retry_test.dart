import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/routes/onboarding/custom_course_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// A choreo 429 is transient, and the server says exactly how transient: its
/// `Retry-After` is the earliest moment a retry can succeed. The word card
/// used to surface the 429 as a red error the moment it landed (#8794);
/// `BaseRepo` now waits out that header once, for the repos that opt in, when
/// it is short enough that the card's shimmer is still honest.
///
/// These drive the real singletons through a `MockClient` installed for the
/// zone, so `Requests` and the header parsing run for real and the assertions
/// are about the contract callers see rather than a stubbed fetch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';

  /// Every wait `BaseRepo` asked for, in order. Recorded instead of slept, so
  /// the tests can assert the wait IS the header rather than merely that some
  /// wait happened.
  final waits = <Duration>[];

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
    waits.clear();
    BaseRepo.delay = (duration) async => waits.add(duration);
  });

  tearDown(() => BaseRepo.delay = Future.delayed);

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
  const contentType = {'content-type': 'application/json; charset=utf-8'};

  Response ok(BaseRequest request) => Response(
    jsonEncode({
      'emoji': ['🙂'],
      'meaning': 'a word',
    }),
    200,
    request: request,
    headers: contentType,
  );

  /// Choreo's limiter rejection. [retryAfter] null is a choreo that predates
  /// 2-step-choreographer#3193 and sends no header.
  Response tooMany(BaseRequest request, {String? retryAfter}) => Response(
    jsonEncode({'detail': 'Rate limit exceeded. Please slow down.'}),
    429,
    request: request,
    headers: {...contentType, 'retry-after': ?retryAfter},
  );

  group('a repo that opts into the rate-limit retry', () {
    test('waits exactly the Retry-After, then returns the retry', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient(
          (r) async => ++calls == 1 ? tooMany(r, retryAfter: '3') : ok(r),
        ),
      );

      // The server's number, not a guess: retrying sooner is the load spike
      // the header exists to prevent.
      expect(waits, [const Duration(seconds: 3)]);
      expect(calls, 2);
      expect(result.isError, isFalse);
      expect(result.asValue!.value.meaning, 'a word');
    });

    test('does not retry when the 429 carries no Retry-After', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((r) async {
          calls++;
          return tooMany(r);
        }),
      );

      // No advice means no guess: the card gets the 429 exactly as it did
      // before the retry existed.
      expect(waits, isEmpty);
      expect(calls, 1);
      expect(PangeaHttpException.statusCodeOf(result.asError?.error), 429);
    });

    test('surfaces the 429 at once when Retry-After is past the cap', () async {
      var calls = 0;
      final tooLong = BaseRepo.maxRateLimitWait + const Duration(seconds: 1);
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((r) async {
          calls++;
          return tooMany(r, retryAfter: '${tooLong.inSeconds}');
        }),
      );

      // Neither waited for (the card would read as hung) nor retried early
      // (that would be a guess), so it fails straight away.
      expect(waits, isEmpty);
      expect(calls, 1);
      expect(PangeaHttpException.statusCodeOf(result.asError?.error), 429);
    });

    test('retries a Retry-After exactly at the cap', () async {
      var calls = 0;
      final atCap = BaseRepo.maxRateLimitWait.inSeconds;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient(
          (r) async => ++calls == 1 ? tooMany(r, retryAfter: '$atCap') : ok(r),
        ),
      );

      expect(waits, [BaseRepo.maxRateLimitWait]);
      expect(result.isError, isFalse);
    });

    test('surfaces the error when the retry is throttled too', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((r) async {
          calls++;
          return tooMany(r, retryAfter: '1');
        }),
      );

      // One retry, then the real error — never a loop.
      expect(calls, 2);
      expect(waits, [const Duration(seconds: 1)]);
      expect(PangeaHttpException.statusCodeOf(result.asError?.error), 429);
    });

    test('does not retry a failure that is not a throttle', () async {
      var calls = 0;
      final result = await runWithClient(
        () => LemmaInfoRepo.instance.get(lemmaRequest()),
        () => MockClient((r) async {
          calls++;
          // A header on a non-429 is not a throttle and earns no retry.
          return Response('', 503, request: r, headers: {'retry-after': '1'});
        }),
      );

      expect(calls, 1);
      expect(waits, isEmpty);
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
        final results = await runWithClient(
          () => Future.wait([
            LemmaInfoRepo.instance.get(request),
            LemmaInfoRepo.instance.get(request),
          ]),
          () => MockClient(
            (r) async => ++calls == 1 ? tooMany(r, retryAfter: '1') : ok(r),
          ),
        );

        expect(
          calls,
          2,
          reason: 'the two callers share one fetch and one retry',
        );
        expect(results.every((r) => !r.isError), isTrue);
      },
    );
  });

  test('a repo that does not opt in surfaces the 429 unchanged', () async {
    var calls = 0;
    final result = await runWithClient(
      () => CustomCourseRepo.instance.get(
        CustomCourseRequestModel(
          name: 'Course ${seq++}',
          languagePair: 'en-es',
          languageLevel: LanguageLevelTypeEnum.a1,
          institution: 'Test School',
          goals: 'Order coffee in Spanish',
        ),
      ),
      () => MockClient((r) async {
        calls++;
        return tooMany(r, retryAfter: '1');
      }),
    );

    expect(calls, 1);
    expect(waits, isEmpty);
    expect(PangeaHttpException.statusCodeOf(result.asError?.error), 429);
  });
}
