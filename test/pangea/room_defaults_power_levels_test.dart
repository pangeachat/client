import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/constants/default_power_level.dart';

void main() {
  group('RoomDefaults.defaultPowerLevelsContent', () {
    test('no-arg call matches the legacy template with no users key', () {
      final content = RoomDefaults.defaultPowerLevelsContent();
      expect(content.containsKey('users'), isFalse);
      expect(content['state_default'], 50);
      expect(content['users_default'], 0);
      expect(content['events']['m.room.power_levels'], 100);
    });

    test('bot grant includes the creator at 100 and the bot at 50', () {
      // Synapse applies power_level_content_override as a shallow top-level
      // merge: supplying "users" replaces the generated {creator: 100}, so
      // the creator must be re-included or room creation breaks.
      final content = RoomDefaults.defaultPowerLevelsContent(
        ownUserId: '@teacher:staging.pangea.chat',
        botUserId: '@bot:staging.pangea.chat',
      );
      expect(content['users'], {
        '@teacher:staging.pangea.chat': 100,
        '@bot:staging.pangea.chat': 50,
      });
    });

    test('bot id without a creator id emits no users key', () {
      // Emitting {bot: 50} alone would wipe the creator's 100 (shallow merge)
      // and leave the room unmanageable — refuse the partial form.
      final content = RoomDefaults.defaultPowerLevelsContent(
        botUserId: '@bot:staging.pangea.chat',
      );
      expect(content.containsKey('users'), isFalse);
    });
  });
}
