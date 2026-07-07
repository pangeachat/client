import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';

/// The 404-vs-transient split behind the removed-activity fallback ladder
/// (activities.instructions.md): only a confirmed 404 may walk the ladder
/// (embedded state plan → archived view) or claim "no longer supported";
/// every other failure stays a retryable error, so an outage can never
/// mislabel healthy activities as removed. 404s are also expected data state
/// (old rooms referencing removed activities), not code breakage — they log
/// as warnings, not Sentry errors.
void main() {
  group('ActivityPlanRepo.classifyLookupError', () {
    test('404 is a confirmed miss — the only status that walks the ladder', () {
      expect(
        ActivityPlanRepo.classifyLookupError(Response('not found', 404)),
        ActivityPlanLookupStatus.removed,
      );
    });

    test('server errors are transient, never removed', () {
      expect(
        ActivityPlanRepo.classifyLookupError(Response('boom', 500)),
        ActivityPlanLookupStatus.failed,
      );
      expect(
        ActivityPlanRepo.classifyLookupError(Response('bad gateway', 502)),
        ActivityPlanLookupStatus.failed,
      );
    });

    test('timeouts and non-HTTP errors are transient, never removed', () {
      expect(
        ActivityPlanRepo.classifyLookupError(TimeoutException('slow')),
        ActivityPlanLookupStatus.failed,
      );
      expect(
        ActivityPlanRepo.classifyLookupError(Exception('offline')),
        ActivityPlanLookupStatus.failed,
      );
    });
  });

  group('BaseRepo.errorLevel — Sentry severity', () {
    test('404 logs as warning (expected data state, not breakage)', () {
      expect(
        BaseRepo.errorLevel(Response('not found', 404)),
        SentryLevel.warning,
      );
    });

    test('timeouts log as warning', () {
      expect(
        BaseRepo.errorLevel(TimeoutException('slow')),
        SentryLevel.warning,
      );
    });

    test('other failures stay errors', () {
      expect(BaseRepo.errorLevel(Response('boom', 500)), SentryLevel.error);
      expect(BaseRepo.errorLevel(Exception('parse')), SentryLevel.error);
    });
  });
}
