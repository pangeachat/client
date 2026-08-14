import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/matrix_session.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

PangeaHttpException _http(int status) => PangeaHttpException(
  statusCode: status,
  method: 'GET',
  path: '/cms/api/quest-plans/{id}',
);

void main() {
  // #8372: `PangeaHttpException: 403 GET /cms/api/quest-plans/{id}` was arriving
  // in Sentry at `error` ("we asked for something we should not have — a code
  // bug"). It is not one. CMS read access to quest-plans is
  // `isMatrixUser || isServiceUser || isAdmin` — no membership scoping exists,
  // so an un-joined learner reading a quest cannot be what the 403 means.
  // Payload simply answers "no authenticated user" with the same 403 it answers
  // "not permitted" with, and there is no 401 anywhere on the CMS surface.
  //
  // The fix DISCRIMINATES the two rather than downgrading either: only a
  // homeserver that positively rejects our token reclassifies the failure.
  group('quest read 403 classification', () {
    Future<bool> rejected() async => true;
    Future<bool> live() async => false;

    test('a 403 with a homeserver-rejected token is token lifecycle', () async {
      final failure = await QuestRepo.classifyQuestReadFailure(
        _http(403),
        tokenRejected: rejected,
      );

      expect(failure.error, isA<SessionExpiredException>());
      // Reported, not swallowed — but at the level the severity table gives
      // token lifecycle, matching its 401 row.
      expect(failure.reportAt, SentryLevel.warning);
    });

    test('a 403 with a live token stays a reported error', () async {
      final original = _http(403);
      final failure = await QuestRepo.classifyQuestReadFailure(
        original,
        tokenRejected: live,
      );

      // The whole point of discriminating: a genuine permission bug must still
      // surface as an error, with the original exception intact.
      expect(failure.error, same(original));
      expect(failure.reportAt, SentryLevel.error);
    });

    test('a 404 is still the silent, benign missing-quest state', () async {
      var probed = false;
      final failure = await QuestRepo.classifyQuestReadFailure(
        _http(404),
        tokenRejected: () async {
          probed = true;
          return true;
        },
      );

      expect(failure.error, isA<MissingQuestException>());
      expect(failure.reportAt, isNull);
      // A 404 needs no session probe — it never reached the auth question.
      expect(probed, isFalse);
    });

    test('a non-403 failure never probes the homeserver', () async {
      var probed = false;
      Future<bool> probe() async {
        probed = true;
        return true;
      }

      final server = await QuestRepo.classifyQuestReadFailure(
        _http(500),
        tokenRejected: probe,
      );
      expect(server.reportAt, SentryLevel.error);

      final rateLimited = await QuestRepo.classifyQuestReadFailure(
        _http(429),
        tokenRejected: probe,
      );
      expect(rateLimited.reportAt, SentryLevel.warning);

      expect(probed, isFalse);
    });
  });

  group('rejected-token errcodes', () {
    test('the homeserver vocabulary for a dead token', () {
      expect(isRejectedTokenErrcode('M_UNKNOWN_TOKEN'), isTrue);
      expect(isRejectedTokenErrcode('M_MISSING_TOKEN'), isTrue);
      expect(isRejectedTokenErrcode('M_FORBIDDEN'), isTrue);
      expect(isRejectedTokenErrcode('M_USER_DEACTIVATED'), isTrue);
    });

    test('an unrelated errcode is not a token rejection', () {
      // Conservative by design: anything we do not positively recognize leaves
      // the failure classified as it was, so a permission bug is never hidden.
      expect(isRejectedTokenErrcode('M_LIMIT_EXCEEDED'), isFalse);
      expect(isRejectedTokenErrcode('M_NOT_FOUND'), isFalse);
      expect(isRejectedTokenErrcode(null), isFalse);
    });
  });

  group('QuestRepo.outline does not cache a session expiry', () {
    const quest = QuestPlan(
      id: 'quest-1',
      name: 'Quest',
      description: '',
      targetLanguage: 'es',
      sequence: [],
    );

    setUp(QuestRepo.resetOutlineCacheForTest);

    tearDown(() {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.debugTokenRejected = null;
      QuestRepo.resetOutlineCacheForTest();
    });

    test('a session expiry is retried, and recovers once refreshed', () async {
      var buildCalls = 0;
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        // The token refresh completes between the two reads.
        if (buildCalls == 1) return Result.error(SessionExpiredException());
        return Result.value(const QuestOutline(quest: quest, groups: []));
      };

      expect((await QuestRepo.outline('quest-1')).isError, isTrue);
      // Unlike a confirmed 404, this must NOT be memoized: the SDK's soft-logout
      // refresh heals it seconds later, and pinning it would leave every quest
      // touched mid-refresh permanently unavailable (#8083's failure mode).
      expect((await QuestRepo.outline('quest-1')).isValue, isTrue);
      expect(buildCalls, 2);
    });
  });
}
