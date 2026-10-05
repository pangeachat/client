import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' hide BaseRequest, BaseResponse;
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

/// #8889: a `BaseRepo` fetch that expires used to throw a message-less
/// [TimeoutException], which on the web has no app frame and so landed in the
/// one unnamed-timeout bucket (CLIENT-AXX) with every other wait in the app.
/// The repo cannot see its subclass's URL, so the carrier it hands to
/// [BaseRepo.fetch] records the call, and the timeout is named after it.
///
/// Sentry is uninitialized here, so the report the repo files no-ops; what is
/// pinned is the exception the caller receives.

class _Req extends BaseRequest {
  @override
  String get storageKey => 'fixed-key';

  @override
  Map<String, dynamic> toJson() => const {};
}

class _Resp extends BaseResponse {
  @override
  Map<String, dynamic> toJson() => const {};
}

/// Never answers, so the repo's own deadline is what ends the fetch. [call]
/// stands in for what [Requests.get] records on the carrier.
class _HangingRepo extends BaseRepo<_Req, _Resp> {
  final String? call;

  _HangingRepo(this.call)
    : super(
        cache: MemoryRepoCache<_Resp>(),
        responseFromJson: (_) => _Resp(),
        cacheDuration: const Duration(minutes: 1),
        timeout: const Duration(milliseconds: 1),
      );

  @override
  Requests createRequests() => Requests(accessToken: 'test-token');

  @override
  Future<Response> fetch(Requests req, _Req request) {
    req.inFlight = call;
    return Completer<Response>().future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BaseRepo fetch timeout', () {
    test('is named after the call the carrier made', () async {
      final result = await _HangingRepo(
        'GET /choreo/v2/activity/{id}',
      ).get(_Req());
      expect(
        result.asError!.error,
        isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          'GET /choreo/v2/activity/{id}',
        ),
      );
    });

    test('still says where it came from when no call was recorded', () async {
      final result = await _HangingRepo(null).get(_Req());
      expect(
        result.asError!.error,
        isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          'BaseRepo.fetch',
        ),
      );
    });
  });

  group('Requests.inFlight', () {
    test('records method and normalized path of the call', () async {
      final req = Requests(accessToken: 'test-token');
      await runWithClient(
        () => req.get(
          url:
              'https://api.pangea.chat/choreo/v2/activity/'
              '98881d89-7195-4928-95ad-3aef0ec3228a?l1=en',
        ),
        () => MockClient((_) async => Response('{}', 200)),
      );
      expect(req.inFlight, 'GET /choreo/v2/activity/{id}');
    });
  });
}
