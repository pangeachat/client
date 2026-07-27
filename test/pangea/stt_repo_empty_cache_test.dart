import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' hide BaseRequest, BaseResponse;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Regression: an exhausted-fallback STT response (`results: []`, HTTP 200)
/// used to THROW at parse, which INCIDENTALLY kept it out of the 10-minute
/// STT cache. R0-2 made the model parse empties gracefully (correct), so
/// `BaseRepo.get` would now memoize the empty success and starve retries for
/// the whole `cacheDuration` — the toolbar path would show "transcription
/// failed" for 10 minutes instead of retrying on the next tap.
///
/// The root fix is a `shouldCache` policy hook on `BaseRepo` (default: cache
/// everything) that `SpeechToTextRepo` overrides to refuse caching an empty
/// response. These tests pin (1) the gate wiring in `get()` via a fake repo
/// driven twice, and (2) the real `SpeechToTextRepo` policy.

class _Req extends BaseRequest {
  @override
  String get storageKey => 'fixed-key';

  @override
  Map<String, dynamic> toJson() => const {};
}

class _Resp extends BaseResponse {
  final List<dynamic> results;

  _Resp({required this.results});

  factory _Resp.fromJson(Map<String, dynamic> json) =>
      _Resp(results: json['results'] as List<dynamic>);

  @override
  Map<String, dynamic> toJson() => {'results': results};
}

/// Drives the real `BaseRepo.get()` without the Matrix god-object: overrides
/// the `createRequests` seam so `_fetch` never reads `MatrixState`, and counts
/// backend calls. Mirrors `SpeechToTextRepo`'s policy: never memoize an empty
/// success.
class _CountingRepo extends BaseRepo<_Req, _Resp> {
  int fetchCount = 0;
  final List<String> bodies;

  _CountingRepo(this.bodies)
    : super(
        cache: MemoryRepoCache<_Resp>(),
        responseFromJson: _Resp.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  @override
  Requests createRequests() => Requests(accessToken: 'test-token');

  @override
  Future<Response> fetch(Requests req, _Req request) async {
    final body =
        bodies[fetchCount < bodies.length ? fetchCount : bodies.length - 1];
    fetchCount++;
    return Response(body, 200);
  }

  @override
  bool shouldCache(_Resp response) => response.results.isNotEmpty;
}

void main() {
  test(
    'empty response is not cached; the next get refetches, then non-empty caches',
    () async {
      final repo = _CountingRepo([
        jsonEncode({'results': <dynamic>[]}), // 1st fetch: exhausted fallback
        jsonEncode({
          'results': [1, 2],
        }), // 2nd fetch: real transcript
        jsonEncode({
          'results': [9],
        }), // 3rd fetch must NOT happen
      ]);

      // First call fetches the empty response.
      final first = await repo.get(_Req());
      expect(first.asValue!.value.results, isEmpty);
      expect(repo.fetchCount, 1);

      // Empty was NOT cached, so the next get hits the backend again and gets
      // the real transcript (pre-fix this returned the cached empty).
      final second = await repo.get(_Req());
      expect(second.asValue!.value.results, [1, 2]);
      expect(repo.fetchCount, 2);

      // The non-empty response WAS cached, so a third get is served from cache
      // with no additional fetch.
      final third = await repo.get(_Req());
      expect(third.asValue!.value.results, [1, 2]);
      expect(repo.fetchCount, 2);
    },
  );

  test(
    'SpeechToTextRepo refuses to cache an empty (exhausted-fallback) response',
    () {
      final empty = SpeechToTextResponseModel(results: const []);
      final nonEmpty = SpeechToTextResponseModel(
        results: [
          SpeechToTextResult(
            transcripts: [
              Transcript(
                text: 'hola',
                confidence: 100,
                sttTokens: const [],
                langCode: 'es',
                wordsPerHr: null,
              ),
            ],
          ),
        ],
      );

      expect(SpeechToTextRepo.instance.shouldCache(empty), isFalse);
      expect(SpeechToTextRepo.instance.shouldCache(nonEmpty), isTrue);
    },
  );
}
