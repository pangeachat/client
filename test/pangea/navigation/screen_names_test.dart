import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/screen_names.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token.dart';

/// The GA screen-name derivation (google-analytics.instructions.md): token
/// syntax, identity stripped, navigational params kept — including folded and
/// single-column states, which read the same tokens.
void main() {
  String name(String location) => ScreenNames.forWorkspace(Uri.parse(location));

  group('forToken (identity stripped, navigational kept)', () {
    test('the doc examples hold', () {
      expect(ChatsPanelToken().screenName, 'chats');
      expect(RoomPanelToken(RoomTokenParam.parse('!abc')).screenName, 'room');
      expect(
        RoomPanelToken(RoomTokenParam.parse('!abc/search')).screenName,
        'room:search',
      );
      expect(
        CoursePanelToken(CourseDetailsTokenParam.parse('more')).screenName,
        'course:more',
      );
      expect(
        CoursePagePanelToken(RoomSubpageTokenParam.parse('invite')).screenName,
        'coursepage:invite',
      );
      expect(
        SettingsPagePanelToken(
          SettingsTokenParam.parse('security/3pid'),
        ).screenName,
        'settingspage:security/3pid',
      );
      expect(
        SettingsPagePanelToken(
          SettingsTokenParam.parse('subscription'),
        ).screenName,
        'settingspage:subscription',
      );
      expect(
        AnalyticsPanelToken(AnalyticsTokenParam.parse('vocab')).screenName,
        'analytics:vocab',
      );
      expect(
        AnalyticsPracticePanelToken(
          AnalyticsPracticeTokenParam.parse('grammar'),
        ).screenName,
        'practice:grammar',
      );
    });

    test('addcoursepage keeps subpage and leaf, drops ids and filters', () {
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse('own'),
        ).screenName,
        'addcoursepage:own',
      );
      // Language filter and all-languages flag are dropped.
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse('own.les-ES.a'),
        ).screenName,
        'addcoursepage:own',
      );
      // The created course's id is identity; the pushed page keeps its leaf.
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse(
            'own/30dbdcfc-0f8c-4b7f-bdf8-f15d86c8cb24.les',
          ),
        ).screenName,
        'addcoursepage:own/preview',
      );
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse(
            'own/30dbdcfc-0f8c-4b7f-bdf8-f15d86c8cb24/invite',
          ),
        ).screenName,
        'addcoursepage:own/invite',
      );
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse('browse'),
        ).screenName,
        'addcoursepage:browse',
      );
      // The previewed room's id is identity.
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse('browse/!abc.les'),
        ).screenName,
        'addcoursepage:browse/preview',
      );
      // The private join code is identity (and secret) — never in a name.
      expect(
        AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse('private.jABC123'),
        ).screenName,
        'addcoursepage:private',
      );
    });

    test('identity params never leak into a name', () {
      expect(
        VocabAnalyticsPanelToken(
          VocabAnalyticsTokenParam.parse('abrigadoro.adj'),
        ).screenName,
        'vocab',
      );
      expect(
        GrammarAnalyticsPanelToken(
          GrammarAnalyticsTokenParam.parse('ser.aux'),
        ).screenName,
        'grammar',
      );
      expect(
        ActivityPanelToken(
          ActivityTokenParam.parse('act-1.r!sess.l'),
        ).screenName,
        'activity',
      );
      expect(
        SessionPanelToken(RoomTokenParam.parse('!room')).screenName,
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
