import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/notifications/communication_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8);

  group('CommunicationPreferences', () {
    test('an empty event refuses nothing', () {
      final preferences = CommunicationPreferences.fromJson({});
      expect(preferences.refusesMissedMessageEmail, isFalse);
    });

    test('reads a missed-message refusal written by the unsubscribe link', () {
      final preferences = CommunicationPreferences.fromJson({
        'version': 1,
        'refused': ['activity_nudges', 'missed_message'],
        'all_off': false,
        'updated_ts': 1759881600000,
        'source': 'unsubscribe_link',
      });
      expect(preferences.refusesMissedMessageEmail, isTrue);
    });

    test('the global off does not refuse missed-message email', () {
      final preferences = CommunicationPreferences.fromJson({
        'refused': <String>[],
        'all_off': true,
      });
      expect(preferences.refusesMissedMessageEmail, isFalse);
    });

    test('a malformed refused list reads as nothing refused', () {
      final preferences = CommunicationPreferences.fromJson({
        'refused': 'missed_message',
      });
      expect(preferences.refusesMissedMessageEmail, isFalse);
    });

    test('refusing keeps the other refusals and the global off', () {
      final preferences = CommunicationPreferences.fromJson({
        'refused': ['suggestions'],
        'all_off': true,
      }).withMissedMessageEmailRefused(true, now);

      expect(preferences.toJson(), {
        'version': 1,
        'refused': ['missed_message', 'suggestions'],
        'all_off': true,
        'updated_ts': now.millisecondsSinceEpoch,
        'source': 'app',
      });
    });

    test('accepting removes only the missed-message refusal', () {
      final preferences = CommunicationPreferences.fromJson({
        'refused': ['missed_message', 'campaigns'],
      }).withMissedMessageEmailRefused(false, now);

      expect(preferences.refusesMissedMessageEmail, isFalse);
      expect(preferences.toJson()['refused'], ['campaigns']);
    });
  });
}
