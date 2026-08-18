import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_request_model.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// `ActivitySummaryRepo` threw the raw `http.Response` on a non-200 and
/// reported every failure at the default `error` level (#8362).
///
/// Two failure shapes reach the same `catch`, and both are covered here:
/// `Requests` throws typed for anything ≥ 400, and the repo's own guard now
/// throws typed for a *success* status the parser cannot consume (201/202/204),
/// which is the only case that guard can still fire on. The `MockClient` is
/// installed for the zone, so `Requests` runs for real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';
  const summaryPath = '/choreo/activity_summary';
  const roomId = '!activity:staging.pangea.chat';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('summary_repo_test');
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

  /// A distinct activity per call — the repo memoizes successes for 10 minutes
  /// on roomId + activityId + langCode.
  var seq = 0;
  ActivitySummaryRequestModel request() => ActivitySummaryRequestModel(
    activity: ActivityPlanModel(
      req: ActivityPlanRequest(
        topic: 'jobs',
        mode: 'Roleplay',
        objective: 'introduce yourself',
        media: MediaEnum.nan,
        cefrLevel: LanguageLevelTypeEnum.a1,
        languageOfInstructions: 'en',
        targetLanguage: 'de',
        numberOfParticipants: 2,
      ),
      title: 'Speed-Dating Interview',
      learningObjective: 'lo',
      instructions: 'i',
      vocab: const [],
      activityId: 'act-${seq++}',
    ),
    activityResults: const [],
    contentFeedback: const [],
  );

  Future<Object?> fetchError(int status, {String body = ''}) async {
    final result = await runWithClient(
      () => ActivitySummaryRepo.get(roomId, request()),
      () => MockClient(
        (request) async => Response(body, status, request: request),
      ),
    );
    return result.asError?.error;
  }

  group('a failed summary fetch', () {
    test('surfaces as Result.error, never as a throw', () async {
      final result = await runWithClient(
        () => ActivitySummaryRepo.get(roomId, request()),
        () =>
            MockClient((request) async => Response('', 500, request: request)),
      );

      expect(result.isError, isTrue);
      expect(result.asError!.error, isA<PangeaHttpException>());
    });

    test('a 4xx/5xx is typed, never the raw response', () async {
      final error = await fetchError(504);

      expect(error, isA<PangeaHttpException>());
      expect(error, isNot(isA<BaseResponse>()));
      expect(error.toString(), isNot(contains('Instance of')));
    });

    test('toString carries status, method, and normalized path', () async {
      expect(
        (await fetchError(500)).toString(),
        'PangeaHttpException: 500 POST $summaryPath',
      );
    });

    test('a non-200 success status is typed too', () async {
      // The only case the repo's own guard can still fire on: `Requests` has
      // already thrown for everything ≥ 400, so a 202 with no parseable body
      // is what reaches it. Before #8362 this threw the response itself.
      for (final status in [201, 202, 204]) {
        final error = await fetchError(status);
        expect(error, isA<PangeaHttpException>());
        expect(
          error.toString(),
          'PangeaHttpException: $status POST $summaryPath',
        );
      }
    });

    test('is reported at the shared severity table level', () async {
      for (final status in [401, 404, 410, 429]) {
        expect(
          PangeaHttpException.severityOf(await fetchError(status)),
          SentryLevel.warning,
          reason: '$status is routine, not a page',
        );
      }
      for (final status in [400, 403, 422, 500, 502]) {
        expect(
          PangeaHttpException.severityOf(await fetchError(status)),
          SentryLevel.error,
          reason: '$status is a code bug or a backend regression',
        );
      }
    });

    test('never carries the response body', () async {
      final error =
          await fetchError(
                500,
                body: jsonEncode({'summary': 'learner conversation text'}),
              )
              as PangeaHttpException;

      expect(error.detail, isNull);
      expect(error.toString(), isNot(contains('learner conversation text')));
    });
  });

  test('a 200 parses into the response model', () async {
    final result = await runWithClient(
      () => ActivitySummaryRepo.get(roomId, request()),
      () => MockClient(
        (request) async => Response(
          jsonEncode({'participants': [], 'summary': 'Gut gemacht!'}),
          200,
          request: request,
        ),
      ),
    );

    expect(result.asValue!.value.summary, 'Gut gemacht!');
  });
}
