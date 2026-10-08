import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/user/pangea_push_rules_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  // A ring that ends unanswered leaves a card, and the card is what tells a
  // phone that rang while the app was closed to say "Missed call". The rule
  // has to match a missed call's card and nothing else: an answered or
  // declined call says nothing the learner does not already know.
  test('a missed call card pushes silently, and only a missed one', () async {
    final client = await getTestClient();
    // The fake server knows none of this app's rules, and one refused write
    // stops the rest.
    for (final id in [
      PangeaEventTypes.analyticsInviteRule,
      PangeaEventTypes.textToSpeechRule,
      PangeaEventTypes.callNotification,
      PangeaEventTypes.missedCallRule,
    ]) {
      FakeMatrixApi
          .currentApi!
          .api['PUT']!['/client/v3/pushrules/global/override/$id'] = (_) =>
          <String, Object?>{};
    }
    await client.setPangeaPushRules();

    final put = FakeMatrixApi.calledEndpoints.entries.firstWhere(
      (e) => e.key.endsWith(
        '/pushrules/global/override/${PangeaEventTypes.missedCallRule}',
      ),
    );
    final rule = jsonDecode(put.value.last as String) as Map<String, Object?>;
    expect(rule['conditions'], [
      {'kind': 'event_match', 'key': 'type', 'pattern': PangeaEventTypes.call},
      {'kind': 'event_property_is', 'key': 'content.answered', 'value': false},
      {'kind': 'event_property_is', 'key': 'content.declined', 'value': false},
    ]);
    // Notify with no sound tweak: it follows a ring that has just stopped.
    expect(rule['actions'], [
      'notify',
      {'set_tweak': 'highlight', 'value': false},
    ]);
    await client.dispose(closeDatabase: true);
  });
}
