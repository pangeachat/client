import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import '../get_test_client.dart';

/// #9732 — listeners that run just after logout look up the learner's
/// analytics room. A logged-out client has none, so null is the answer, not a
/// report: each caller filed its own Sentry issue (CLIENT-F41, F4Z, F4R, F5J,
/// F5K).
void main() {
  late Client client;
  late List<String> errors;
  final debugPrintBefore = debugPrint;
  final de = LanguageModel(langCode: 'de', displayName: 'German');

  setUp(() async {
    client = await getTestClient();
    errors = [];
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.startsWith('error message:')) {
        errors.add(message);
      }
    };
  });

  tearDown(() async {
    debugPrint = debugPrintBefore;
    await client.dispose();
  });

  test(
    'a logged-out client has no analytics room, and nothing is reported',
    () async {
      await client.logout();

      expect(client.ownAnalyticsRoomLocal(lang: de), isNull);
      expect(errors, isEmpty);
    },
  );

  test('a logged-in client with no user ID is still reported', () async {
    await client.logout();
    client.accessToken = 'abcd';

    expect(client.ownAnalyticsRoomLocal(lang: de), isNull);
    expect(errors, ['error message: userID null in myAnalyticsRoomLocal']);
  });
}
