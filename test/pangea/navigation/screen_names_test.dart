import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/screen_names.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token_param.dart';

/// The GA screen-name derivation (google-analytics.instructions.md): token
/// syntax, identity stripped, navigational params kept — including folded and
/// single-column states, which read the same tokens.
void main() {
  String name(String location) => ScreenNames.forWorkspace(Uri.parse(location));

  group('forToken (identity stripped, navigational kept)', () {
    test('the doc examples hold', () {
      expect(ScreenNames.forToken(const PanelToken('chats')), 'chats');
      expect(
        ScreenNames.forToken(PanelToken('room', RoomTokenParam.parse('!abc'))),
        'room',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('room', RoomTokenParam.parse('!abc/search')),
        ),
        'room:search',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('course', CourseDetailsTokenParam.parse('more')),
        ),
        'course:more',
      );
      expect(
        ScreenNames.forToken(
          PanelToken(
            'coursepage',
            CourseDetailsSubpageTokenParam.parse('invite'),
          ),
        ),
        'coursepage:invite',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('settingspage', SettingsTokenParam.parse('security/3pid')),
        ),
        'settingspage:security/3pid',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('settingspage', SettingsTokenParam.parse('subscription')),
        ),
        'settingspage:subscription',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('analytics', AnalyticsTokenParam.parse('vocab')),
        ),
        'analytics:vocab',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('practice', AnalyticsPracticeTokenParam.parse('grammar')),
        ),
        'practice:grammar',
      );
    });

    test('identity params never leak into a name', () {
      expect(
        ScreenNames.forToken(
          PanelToken('vocab', VocabAnalyticsTokenParam.parse('abrigadoro.adj')),
        ),
        'vocab',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('grammar', GrammarAnalyticsTokenParam.parse('ser.aux')),
        ),
        'grammar',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('activity', ActivityTokenParam.parse('act-1.r!sess.l')),
        ),
        'activity',
      );
      expect(
        ScreenNames.forToken(
          PanelToken('session', RoomTokenParam.parse('!room')),
        ),
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
      expect(name('/?right=vocab:abrigadoro.adj,analytics:vocab'), 'vocab');
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
      expect(name('/?left=chats,room:!abc&right=analytics:vocab'), 'room');
    });

    test('the activity plan reads as activity whatever its bindings', () {
      expect(name('/?c=!s&left=activity:act-1.r!sess.l'), 'activity');
    });
  });
}
