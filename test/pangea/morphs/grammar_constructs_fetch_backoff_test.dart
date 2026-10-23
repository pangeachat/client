import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// #9604: a failed grammar-labels fetch was forgotten at once, so every surface
/// that reads the labels — app start, a language change, the Grammar analytics
/// details, practice generation — sent the request again. One learner whose
/// pair the server cannot build sent it five times in nine minutes, each a
/// ~7 s LLM call there. After a failure the repo now holds the pair for
/// [GrammarConstructsRepo.retryFailedFetchAfter] and answers from the hold.
///
/// Drives the real singleton behind a mock backend. Sentry is uninitialized,
/// so the one report the repo files per failure no-ops.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Before the singleton is touched: its persistent cache builds a GetStorage
  // container on construction, which reaches for path_provider at once.
  final tempDir = Directory.systemTemp.createTempSync('grammar_backoff_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = GrammarConstructsRepo.instance;
  var clock = DateTime(2026, 10, 22, 12);

  setUpAll(() async {
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    // The request URL reads the choreo host from dotenv.
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('grammar_constructs_storage');
  });

  setUp(() async {
    clock = DateTime(2026, 10, 22, 12);
    RateLimitPause.now = () => clock;
    await repo.clearCache();
  });

  tearDownAll(() => RateLimitPause.now = DateTime.now);

  GrammarConstructsRequest pair(String l2, String l1) =>
      GrammarConstructsRequest(targetLanguage: l2, userL1: l1);

  /// Runs [body] against a backend that answers every request with a 500,
  /// returning how many requests reached it.
  Future<int> requestsSent(Future<void> Function() body) async {
    var sent = 0;
    await http.runWithClient(
      body,
      () => MockClient((request) async {
        sent++;
        return http.Response('{"detail":"max tries exhausted"}', 500);
      }),
    );
    return sent;
  }

  group('a failed grammar-labels fetch', () {
    test('is not sent again on the next read of the same pair', () async {
      late Object first;
      late Object second;
      final sent = await requestsSent(() async {
        first = (await repo.get(pair('ar', 'es'))).asError!.error;
        second = (await repo.get(pair('ar', 'es'))).asError!.error;
      });

      expect(sent, 1, reason: 'the second read must answer from the hold');
      expect(PangeaHttpException.statusCodeOf(first), 500);
      expect(
        second,
        same(first),
        reason: 'the held read returns the failure the caller was told about',
      );
    });

    test('is sent again once the hold lapses', () async {
      final sent = await requestsSent(() async {
        await repo.get(pair('ar', 'es'));
        clock = clock.add(
          GrammarConstructsRepo.retryFailedFetchAfter +
              const Duration(minutes: 1),
        );
        await repo.get(pair('ar', 'es'));
      });

      expect(sent, 2);
    });

    test('holds only its own language pair', () async {
      final sent = await requestsSent(() async {
        await repo.get(pair('ar', 'es'));
        await repo.get(pair('ko', 'zh'));
      });

      expect(sent, 2);
    });

    test('does not hold a forced refresh', () async {
      final sent = await requestsSent(() async {
        await repo.get(pair('ar', 'es'));
        await repo.get(pair('ar', 'es'), forceRefresh: true);
      });

      expect(sent, 2);
    });
  });
}
