import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/mission_xp_cache.dart';

/// Practice credit (org activities doc, "Practice credit"): a use that names
/// its room credits that room; a room-less practice use on a word credits
/// every room where the learner wrote that word, and nowhere else.
void main() {
  test('room-less practice XP credits every room the word was written in', () {
    final credited = MissionXpCache.credit(
      {'r1': 100, 'r2': 50},
      {'hola': 10, 'gracias': 5},
      {
        'hola': {'r1', 'r2'},
        'adios': {'r1'},
      },
    );
    expect(credited, {'r1': 110, 'r2': 60});
  });

  test('a room with no chat XP still receives practice credit', () {
    final credited = MissionXpCache.credit(
      const {},
      {'hola': 10},
      {
        'hola': {'r1'},
      },
    );
    expect(credited, {'r1': 10});
  });
}
