import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/mission_due_date.dart';

/// A Mission's due date reads as wall-clock time in the course's zone. The
/// dashboard saves the zone name its browser offers (Intl), and Chrome's Intl
/// still names some zones by their old IANA ids; this app's zone data knows
/// only the current ids, so those must still resolve to the course's zone
/// rather than silently showing the viewer's own time.
void main() {
  // 2026-10-20 12:00 UTC.
  final dueAt = DateTime.utc(2026, 10, 20, 12);

  ({int hour, int minute}) wall(String zone) {
    final t = missionDueWallTime(dueAt, zone);
    return (hour: t.hour, minute: t.minute);
  }

  test('a current zone id reads in that zone', () {
    expect(wall('Europe/Madrid'), (hour: 14, minute: 0));
    expect(wall('Asia/Kolkata'), (hour: 17, minute: 30));
  });

  test(
    'the old ids a browser offers read in the same zone as the new ones',
    () {
      const pairs = {
        'Asia/Calcutta': 'Asia/Kolkata',
        'Asia/Katmandu': 'Asia/Kathmandu',
        'Asia/Saigon': 'Asia/Ho_Chi_Minh',
        'Europe/Kiev': 'Europe/Kyiv',
        'America/Buenos_Aires': 'America/Argentina/Buenos_Aires',
        'America/Catamarca': 'America/Argentina/Catamarca',
        'America/Cordoba': 'America/Argentina/Cordoba',
        'America/Jujuy': 'America/Argentina/Jujuy',
        'America/Mendoza': 'America/Argentina/Mendoza',
        'America/Indianapolis': 'America/Indiana/Indianapolis',
        'America/Louisville': 'America/Kentucky/Louisville',
        'America/Coral_Harbour': 'America/Atikokan',
        'Atlantic/Faeroe': 'Atlantic/Faroe',
        'Africa/Asmera': 'Africa/Asmara',
        'Pacific/Ponape': 'Pacific/Pohnpei',
        'Pacific/Truk': 'Pacific/Chuuk',
      };
      for (final e in pairs.entries) {
        expect(wall(e.key), wall(e.value), reason: e.key);
      }
      expect(wall('Asia/Calcutta'), (hour: 17, minute: 30));
    },
  );
}
