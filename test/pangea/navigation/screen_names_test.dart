import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/screen_names.dart';

/// The GA screen-name derivation (google-analytics.instructions.md): token
/// syntax, identity stripped, navigational params kept — including folded and
/// single-column states, which read the same tokens.
void main() {
  String name(String location) => ScreenNames.forWorkspace(Uri.parse(location));

  group('forToken (identity stripped, navigational kept)', () {
    test('the doc examples hold', () {
      expect(ScreenNames.forToken(const PanelToken('chats')), 'chats');
      expect(ScreenNames.forToken(const PanelToken('room', '!abc')), 'room');
      expect(
        ScreenNames.forToken(const PanelToken('room', '!abc/search')),
        'room:search',
      );
      expect(
        ScreenNames.forToken(const PanelToken('course', 'more')),
        'course:more',
      );
      expect(
        ScreenNames.forToken(const PanelToken('coursepage', 'invite')),
        'coursepage:invite',
      );
      expect(
        ScreenNames.forToken(const PanelToken('settingspage', 'security/3pid')),
        'settingspage:security/3pid',
      );
      expect(
        ScreenNames.forToken(const PanelToken('settingspage', 'subscription')),
        'settingspage:subscription',
      );
      expect(
        ScreenNames.forToken(const PanelToken('analytics', 'vocab')),
        'analytics:vocab',
      );
      expect(
        ScreenNames.forToken(const PanelToken('practice', 'grammar')),
        'practice:grammar',
      );
    });

    test('identity params never leak into a name', () {
      expect(
        ScreenNames.forToken(const PanelToken('vocab', 'abrigadoro.adj')),
        'vocab',
      );
      expect(
        ScreenNames.forToken(const PanelToken('grammar', 'ser.aux')),
        'grammar',
      );
      expect(
        ScreenNames.forToken(const PanelToken('activity', 'act-1.r!sess.l')),
        'activity',
      );
      expect(
        ScreenNames.forToken(const PanelToken('session', '!room')),
        'session',
      );
    });
  });

  group('forWorkspace (the focused leaf names the screen)', () {
    test('the bare map is world', () {
      expect(name('/'), 'world');
      expect(name('/?c=!s'), 'world'); // context alone opens nothing
    });

    test('a child wins over its open parent', () {
      expect(name('/?left=chats'), 'chats');
      expect(name('/?left=chats,room:!abc'), 'room');
      expect(name('/?right=analytics:vocab'), 'analytics:vocab');
      expect(
        name('/?right=vocab:abrigadoro.adj,analytics:vocab'),
        'vocab',
      );
      expect(
        name('/?right=settingspage:security/3pid,settings'),
        'settingspage:security/3pid',
      );
      expect(
        name('/?c=!s&left=course:more,coursepage:invite'),
        'coursepage:invite',
      );
    });

    test('independent panels tie-break by registry priority', () {
      // A live room (80) out-ranks an analytics summary (40) when both are
      // leaves — matching the narrow-mode cold-start focus rule.
      expect(
        name('/?left=chats,room:!abc&right=analytics:vocab'),
        'room',
      );
    });

    test('the activity plan reads as activity whatever its bindings', () {
      expect(name('/?c=!s&left=activity:act-1.r!sess.l'), 'activity');
    });
  });
}
