import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_response_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// `CustomCourseRepo` used to hand-roll its own in-flight cache and error
/// handling, throw the raw `http.Response` on a non-200, and report every
/// failure at the default `error` level (#8362). It now extends `BaseRepo`,
/// which is where the doc puts that behavior
/// (repos-and-error-handling.instructions.md § Adoption).
///
/// These tests drive the real singleton through a `MockClient` installed for
/// the zone, so `Requests` runs for real and the assertions are about the
/// contract callers see — not about a stubbed fetch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';
  const requestPath = '/choreo/courses/request';

  setUpAll(() async {
    // Environment.appConfigOverride builds a GetStorage('env_override') box,
    // which reaches for path_provider on construction.
    final tempDir = await Directory.systemTemp.createTemp('custom_course_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'syt_test_token',
    );
  });

  setUp(() => dotenv.testLoad(mergeWith: {'CHOREO_API': choreoApi}));

  /// A distinct request per call, so the singleton's in-flight dedupe never
  /// hands one test the previous test's future.
  var seq = 0;
  CustomCourseRequestModel request() => CustomCourseRequestModel(
    name: 'Course ${seq++}',
    languagePair: 'en-es',
    languageLevel: LanguageLevelTypeEnum.a1,
    institution: 'Test School',
    goals: 'Order coffee in Spanish',
  );

  Future<Object?> fetchError(int status, {String body = ''}) async {
    final result = await runWithClient(
      () => CustomCourseRepo.instance.get(request()),
      () => MockClient(
        (request) async => Response(body, status, request: request),
      ),
    );
    return result.asError?.error;
  }

  group('a failed course request', () {
    test('surfaces as Result.error, never as a throw', () async {
      final result = await runWithClient(
        () => CustomCourseRepo.instance.get(request()),
        () =>
            MockClient((request) async => Response('', 500, request: request)),
      );

      expect(result.isError, isTrue);
      expect(result.asError!.error, isA<PangeaHttpException>());
    });

    test('is typed, never the raw response', () async {
      final error = await fetchError(503);

      expect(error, isA<PangeaHttpException>());
      expect(error, isNot(isA<BaseResponse>()));
      expect(error.toString(), isNot(contains('Instance of')));
    });

    test('toString carries status, method, and normalized path', () async {
      expect(
        (await fetchError(500)).toString(),
        'PangeaHttpException: 500 POST $requestPath',
      );
    });

    test('appends the backend detail, capped, never the body', () async {
      final error =
          await fetchError(
                422,
                body: jsonEncode({
                  'detail': 'goals too long',
                  'echo': 'learner-entered text',
                }),
              )
              as PangeaHttpException;

      expect(
        error.toString(),
        'PangeaHttpException: 422 POST $requestPath — goals too long',
      );
      expect(error.toString(), isNot(contains('learner-entered text')));
    });

    test('is reported at the shared severity table level', () async {
      // BaseRepo.errorLevel is what the repo passes to ErrorHandler.logError.
      for (final status in [401, 404, 410, 429]) {
        expect(
          BaseRepo.errorLevel((await fetchError(status))!),
          SentryLevel.warning,
          reason: '$status is routine, not a page',
        );
      }
      for (final status in [400, 403, 422, 500, 502]) {
        expect(
          BaseRepo.errorLevel((await fetchError(status))!),
          SentryLevel.error,
          reason: '$status is a code bug or a backend regression',
        );
      }
    });
  });

  group('a successful course request', () {
    test('parses into the response model', () async {
      final result = await runWithClient(
        () => CustomCourseRepo.instance.get(request()),
        () => MockClient(
          (request) async => Response(
            jsonEncode({'id': 'course-1', 'status': 'generating'}),
            200,
            request: request,
          ),
        ),
      );

      expect(result.asValue!.value.id, 'course-1');
      expect(result.asValue!.value.status, 'generating');
    });

    test('is never memoized', () async {
      // Each submission is its own backend side effect, and `generating` goes
      // stale immediately — so the same request must reach the server twice.
      final req = request();
      var posts = 0;
      final client = MockClient((request) async {
        posts++;
        return Response(
          jsonEncode({'id': 'course-$posts', 'status': 'generating'}),
          200,
          request: request,
        );
      });

      await runWithClient(
        () => CustomCourseRepo.instance.get(req),
        () => client,
      );
      final second = await runWithClient(
        () => CustomCourseRepo.instance.get(req),
        () => client,
      );

      expect(posts, 2);
      expect(second.asValue!.value.id, 'course-2');
    });

    test('shouldCache refuses to pin a submission', () {
      expect(
        CustomCourseRepo.instance.shouldCache(
          const CustomCourseResponseModel(id: 'x', status: 'generating'),
        ),
        isFalse,
      );
    });
  });
}
