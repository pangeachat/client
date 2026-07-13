import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

void main() {
  Uri u(String s) => Uri.parse(s);

  group('openRight / closeRight', () {
    test('adds a token and round-trips back through the parser', () {
      final loc = WorkspaceNav.openRight(
        u('/chats'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      expect(parseOpenPanels(u(loc)).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
    });

    test('an encoded construct param survives the add → URL → parse '
        'round-trip', () {
      final token = VocabAnalyticsPanelToken(
        VocabAnalyticsTokenParam.parse('a%2Cb.verb'),
      );
      final loc = WorkspaceNav.openRight(u('/chats'), token);
      expect(parseOpenPanels(u(loc)).right.single, token);
    });

    test('the parser yields master-first regardless of raw insertion order', () {
      // atStart is a raw list insert, but the parser normalizes a registry
      // master/detail pair to master-first, so the summary always precedes its
      // detail in the URL; the renderer blooms the detail left of the edge.
      var loc = WorkspaceNav.openRight(
        u('/chats'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      loc = WorkspaceNav.openRight(
        u(loc),
        VocabAnalyticsPanelToken(VocabAnalyticsTokenParam.parse('hablar')),
        atStart: true,
      );
      expect(parseOpenPanels(u(loc)).right.map((t) => t.type), [
        PanelTypesEnum.analytics,
        PanelTypesEnum.vocab,
      ]);
    });

    test('adding an existing token is idempotent (deduped)', () {
      var loc = WorkspaceNav.openRight(
        u('/chats'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      loc = WorkspaceNav.openRight(
        u(loc),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      expect(parseOpenPanels(u(loc)).right.length, 1);
    });

    test(
      'close removes the token; the key disappears when the list empties',
      () {
        final opened = WorkspaceNav.openRight(
          u('/chats'),
          const AnalyticsPanelToken(
            AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
          ),
        );
        final closed = WorkspaceNav.closeRight(
          u(opened),
          const AnalyticsPanelToken(
            AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
          ),
        );
        expect(parseOpenPanels(u(closed)).right, isEmpty);
        expect(closed, '/chats'); // no dangling ?right=
      },
    );
  });

  group('preserves the rest of the URL', () {
    test('an unrelated query param is kept verbatim', () {
      final loc = WorkspaceNav.openRight(
        u('/courses/!s?activity=abc'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.activities),
        ),
      );
      final parsed = u(loc);
      expect(parsed.queryParameters['activity'], 'abc');
      expect(parseOpenPanels(parsed).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.activities),
        ),
      ]);
      expect(parsed.path, '/courses/!s');
    });

    test('the path is preserved', () {
      final loc = WorkspaceNav.openRight(
        u('/rooms/!abc'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      expect(u(loc).path, '/rooms/!abc');
    });
  });

  group('setRight replaces the whole list (metric switch)', () {
    test('drops the old analytics/detail tokens and seats one summary', () {
      var loc = WorkspaceNav.openRight(
        u('/chats'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      loc = WorkspaceNav.openRight(
        u(loc),
        VocabAnalyticsPanelToken(VocabAnalyticsTokenParam.parse('hablar')),
        atStart: true,
      );
      loc = WorkspaceNav.setRight(u(loc), [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.morphsUsed),
        ),
      ]);
      expect(parseOpenPanels(u(loc)).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.morphsUsed),
        ),
      ]);
    });
  });

  group('single-column mutual close (sections <-> right panels)', () {
    test('setRight closeSections drops the section sheet but keeps a room', () {
      final loc = WorkspaceNav.setRight(u('/?left=chats,room:!abc'), [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ], closeSections: true);
      final lists = parseOpenPanels(u(loc));
      expect(lists.right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
      // The chats SECTION is gone (X-ing analytics reveals the map), but the
      // live conversation persists — the chat-header avatar loop returns to it.
      expect(lists.left, [const RoomPanelToken(RoomTokenParam(id: '!abc'))]);
    });

    test('setRight closeSections drops a course card, keeping the scope', () {
      final loc = WorkspaceNav.setRight(u('/?c=!s&left=course'), [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ], closeSections: true);
      final uri = u(loc);
      expect(parseOpenPanels(uri).left, isEmpty);
      // `?c=` is scope, not a panel — closing panels never resets it.
      expect(uri.queryParameters['c'], '!s');
    });

    test('setRight without the flag keeps sections (column mode)', () {
      final loc = WorkspaceNav.setRight(u('/?left=chats'), [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
      expect(parseOpenPanels(u(loc)).left, [const ChatsPanelToken()]);
    });

    test('openSettings closeSections drops the section sheet', () {
      final loc = WorkspaceNav.openSettings(
        u('/?left=addcourse'),
        closeSections: true,
      );
      final lists = parseOpenPanels(u(loc));
      expect(lists.right, [const SettingsPanelToken()]);
      expect(lists.left, isEmpty);
    });

    test('setSection clearRight drops an open right panel', () {
      final loc = WorkspaceNav.setSection(
        u('/?right=analytics'),
        const ChatsPanelToken(),
        keepRoom: false,
        clearRight: true,
      );
      final lists = parseOpenPanels(u(loc));
      expect(lists.left, [const ChatsPanelToken()]);
      expect(lists.right, isEmpty);
    });

    test('openCourseSection clearRight drops an open right panel', () {
      final loc = WorkspaceNav.openCourseSection(
        u('/?right=settings'),
        '!course',
        keepRoom: false,
        clearRight: true,
      );
      final lists = parseOpenPanels(u(loc));
      expect(lists.left.length, 1);
      expect(lists.right, isEmpty);
      expect(lists.left.single, const CoursePanelToken());
    });
  });

  group('openRoomById (event folds into the room token; no loose params)', () {
    test('a bare call opens the room with no event/body query at all', () {
      final loc = WorkspaceNav.openRoomById(u('/chats'), '!abc');
      final uri = u(loc);
      expect(parseOpenPanels(uri).left, [
        RoomPanelToken(RoomTokenParam.parse('!abc')),
      ]);
      expect(uri.queryParameters['event'], isNull);
      expect(uri.queryParameters['body'], isNull);
    });

    test('event rides the room token param, not a loose ?event= query', () {
      final loc = WorkspaceNav.openRoomById(u('/chats'), '!abc', event: r'$e1');
      final uri = u(loc);
      expect(uri.queryParameters['event'], isNull);
      final room = parseOpenPanels(uri).left.single;

      final param = room.param;
      expect(param, isA<RoomTokenParam>());
      expect((param as RoomTokenParam).eventId, r'$e1');
    });

    test('subPage still pushes normally alongside a room open', () {
      final loc = WorkspaceNav.openRoomById(
        u('/chats'),
        '!abc',
        subPage: 'details',
      );
      final room = parseOpenPanels(u(loc)).left.single;
      final param = room.param;
      expect(param, isA<RoomTokenParam>());
      expect((param as RoomTokenParam).id, '!abc');
      expect((param).subpage, 'details');
    });
  });

  group('openExclusiveLeftRoom (one live session)', () {
    test('opening a room drops any other room but keeps chats/course', () {
      var loc = WorkspaceNav.setLeft(u('/chats'), [
        ChatsPanelToken(),
        RoomPanelToken(RoomTokenParam.parse('!a')),
      ]);
      loc = WorkspaceNav.openExclusiveLeftRoom(
        u(loc),
        RoomPanelToken(RoomTokenParam.parse('!b')),
      );
      final left = parseOpenPanels(u(loc)).left;
      expect(
        left
            .where((t) => t.type == PanelTypesEnum.room)
            .map((t) => t.param)
            .whereType<RoomTokenParam>()
            .map((r) => r.id)
            .toList(),
        ['!b'],
      );
      expect(left.any((t) => t.type == PanelTypesEnum.chats), isTrue);
    });

    test('preserves an open right panel by construction', () {
      final loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/chats?right=analytics:vocab'),
        RoomPanelToken(RoomTokenParam.parse('!a')),
      );
      expect(parseOpenPanels(u(loc)).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
    });
  });

  group('openCourse (open / switch tab)', () {
    test('switching tabs replaces the course token rather than stacking', () {
      // The course id lives in the `?m=course:` map filter; the token param is
      // just the tab (a bare course token with no filter is dropped at parse).
      var loc = WorkspaceNav.openCourseTab(
        u('/?c=!s'),
        tab: SpaceSettingsTabs.chat,
      );
      loc = WorkspaceNav.openCourseTab(
        u(loc),
        tab: SpaceSettingsTabs.participants,
      );
      final courses = parseOpenPanels(
        u(loc),
      ).left.where((t) => t.type == PanelTypesEnum.course).toList();
      expect(courses.length, 1);

      final param = courses.single.param;
      expect(param, isA<CourseDetailsTokenParam>());
      expect(
        (param as CourseDetailsTokenParam).activeTab,
        SpaceSettingsTabs.participants,
      );
    });

    test('keeps a live room beside the course (a course can scope a room)', () {
      // A course-scoped room: the `?m=course:` filter is set, the room is live,
      // and opening the course card keeps the room beside it.
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/?c=!s'),
        RoomPanelToken(RoomTokenParam.parse('!a')),
      );
      loc = WorkspaceNav.openCourseTab(u(loc));
      final left = parseOpenPanels(u(loc)).left;
      expect(left.any((t) => t.type == PanelTypesEnum.room), isTrue);
      expect(left.any((t) => t.type == PanelTypesEnum.course), isTrue);
    });

    test('reopening the course card sheds an open immersive activity (#7385)', () {
      // The in-course "Pick different activity" / "Return to course" exits route
      // through openCourse/openCourseFilter: showing the card is leaving the
      // activity, so the live-view activity token must NOT co-render beside it
      // (it is not a sibling of `course`, so only an explicit drop clears it).
      final fromActivity = u('/?c=!s&left=activity:abc');
      final viaOpenCourse = parseOpenPanels(
        u(WorkspaceNav.openCourseTab(fromActivity)),
      ).left;
      expect(
        viaOpenCourse.any((t) => t.type == PanelTypesEnum.activity),
        isFalse,
      );
      expect(viaOpenCourse.any((t) => t.type == PanelTypesEnum.course), isTrue);

      final viaFilter = parseOpenPanels(
        u(
          WorkspaceNav.openCourse(
            fromActivity,
            '!s',
            tab: SpaceSettingsTabs.course,
          ),
        ),
      ).left;
      expect(viaFilter.any((t) => t.type == PanelTypesEnum.activity), isFalse);
      expect(viaFilter.any((t) => t.type == PanelTypesEnum.course), isTrue);
    });
  });

  group('openConstructDetail (one detail at a time, across columns)', () {
    test(
      'a new construct detail replaces the prior one, keeping the summary',
      () {
        var loc = WorkspaceNav.openRight(
          u('/'),
          const AnalyticsPanelToken(
            AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
          ),
        );

        final vocabConstructId = ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.vocab,
          'hablar',
        );
        loc = WorkspaceNav.openConstructDetail(
          u(loc),
          ConstructTypeEnum.vocab,
          constructId: vocabConstructId,
        );

        final grammarConstructId = ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.morph,
          'verb',
        );
        loc = WorkspaceNav.openConstructDetail(
          u(loc),
          ConstructTypeEnum.morph,
          constructId: grammarConstructId,
        );

        final right = parseOpenPanels(u(loc)).right;
        // exactly one construct detail, blooming left of its kept summary
        expect(
          right
              .where(
                (t) =>
                    t.type == PanelTypesEnum.vocab ||
                    t.type == PanelTypesEnum.grammar,
              )
              .length,
          1,
        );
        expect(
          right.last,
          GrammarAnalyticsPanelToken(GrammarAnalyticsTokenParam.parse('verb')),
        ); // detail after its master (master-first; renderer blooms it left)
        expect(
          right.first.type,
          PanelTypesEnum.analytics,
        ); // summary master, kept + first
      },
    );

    test('cold start seats the detail AND its summary together', () {
      final constructId = ConstructIdentifier.fromTokenParam(
        ConstructTypeEnum.vocab,
        'hablar',
      );
      final loc = WorkspaceNav.openConstructDetail(
        u('/'),
        ConstructTypeEnum.vocab,
        constructId: constructId,
      );

      final right = parseOpenPanels(u(loc)).right;
      expect(right.map((t) => t.type), [
        PanelTypesEnum.analytics,
        PanelTypesEnum.vocab,
      ]); // master-first

      final param = right.first.param;
      expect(param, isA<AnalyticsTokenParam>());
      expect(
        (param as AnalyticsTokenParam).subpage,
        ProgressIndicatorEnum.wordsUsed,
      ); // the seated summary's tab
    });

    test('opening a construct detail closes an open activity session', () {
      // session (left) + a vocab detail open: drilling a new construct drops the
      // session — one detail at a time across columns.
      final constructId = ConstructIdentifier.fromTokenParam(
        ConstructTypeEnum.vocab,
        'hablar',
      );
      var loc = WorkspaceNav.openExclusiveSession(u('/'), '!s');
      loc = WorkspaceNav.openConstructDetail(
        u(loc),
        ConstructTypeEnum.vocab,
        constructId: constructId,
      );
      final lists = parseOpenPanels(u(loc));
      expect(
        lists.left.any((t) => t.type == PanelTypesEnum.session),
        isFalse,
      ); // session gone
      expect(
        lists.right.last,
        VocabAnalyticsPanelToken(VocabAnalyticsTokenParam.parse('hablar')),
      );
    });

    test('a live room chat is NOT closed by opening a construct detail', () {
      final constructId = ConstructIdentifier.fromTokenParam(
        ConstructTypeEnum.vocab,
        'hablar',
      );
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/'),
        RoomPanelToken(RoomTokenParam.parse('!live')),
      );
      loc = WorkspaceNav.openConstructDetail(
        u(loc),
        ConstructTypeEnum.vocab,
        constructId: constructId,
      );
      final lists = parseOpenPanels(u(loc));
      expect(
        lists.left.any((t) => t.type == PanelTypesEnum.room),
        isTrue,
      ); // chat survives
      expect(
        lists.right.last,
        VocabAnalyticsPanelToken(VocabAnalyticsTokenParam.parse('hablar')),
      );
    });
  });

  group('openExclusiveSession (the session shares the detail slot)', () {
    test('opening a session drops an open vocab/grammar detail', () {
      final constructId = ConstructIdentifier.fromTokenParam(
        ConstructTypeEnum.vocab,
        'hablar',
      );
      var loc = WorkspaceNav.openConstructDetail(
        u('/'),
        ConstructTypeEnum.vocab,
        constructId: constructId,
      );
      loc = WorkspaceNav.openExclusiveSession(u(loc), '!s');
      final lists = parseOpenPanels(u(loc));
      expect(
        lists.right.any(
          (t) =>
              t.type == PanelTypesEnum.vocab ||
              t.type == PanelTypesEnum.grammar,
        ),
        isFalse,
      ); // construct detail gone
      expect(lists.left.any((t) => t.type == PanelTypesEnum.session), isTrue);
    });

    test('a session drops another room/session (one live view)', () {
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/'),
        RoomPanelToken(RoomTokenParam.parse('!live')),
      );
      loc = WorkspaceNav.openExclusiveSession(u(loc), '!s');
      final left = parseOpenPanels(u(loc)).left;
      expect(
        left
            .where(
              (t) =>
                  t.type == PanelTypesEnum.room ||
                  t.type == PanelTypesEnum.session,
            )
            .length,
        1,
      );
      expect(left.single, SessionPanelToken(RoomTokenParam.parse('!s')));
    });

    test('opening a session from Stars closes the open course card (#7106)', () {
      // A saved activity opened from the Stars archive takes over the left
      // column: the open course card closes (so the review isn't rendered behind
      // it) while the map scope is kept.
      final loc = WorkspaceNav.openExclusiveSession(
        u('/?c=!s&left=course'),
        '!a',
      );
      final left = parseOpenPanels(u(loc)).left;
      expect(
        left.any((t) => t.type == PanelTypesEnum.course),
        isFalse,
      ); // card closed

      final param = left
          .singleWhere((t) => t.type == PanelTypesEnum.session)
          .param;
      expect(param, isA<RoomTokenParam>());
      expect((param as RoomTokenParam).id, '!a');
      expect(loc.contains('c='), isTrue); // map scope preserved
    });
  });

  group('setLeft / clearLeft', () {
    test('setLeft replaces the whole left list, preserving right', () {
      var loc = WorkspaceNav.setLeft(u('/chats?right=analytics:vocab'), [
        RoomPanelToken(RoomTokenParam.parse('!a')),
        ChatsPanelToken(),
      ]);
      // Replace with a filter-independent left root (a bare course would be
      // dropped at parse for lacking its `?m=course:` filter).
      loc = WorkspaceNav.setLeft(u(loc), const [AddCoursePanelToken()]);
      expect(parseOpenPanels(u(loc)).left, [const AddCoursePanelToken()]);
      expect(parseOpenPanels(u(loc)).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
    });
  });

  group('closeSection (drop a section panel, keep the map filter)', () {
    test(
      'closing a course card keeps its ?m= filter, the room, and the right',
      () {
        final loc = WorkspaceNav.closeSection(
          u('/?c=!s&left=course,room:!a&right=analytics:vocab'),
          const CoursePanelToken(),
        );
        // Scope is independent of panels: the map stays course-scoped (filter
        // survives), the card is gone, the room and right column are kept.
        expect(loc.contains('c='), isTrue);
        final lists = parseOpenPanels(u(loc));
        expect(
          lists.left.any((t) => t.type == PanelTypesEnum.course),
          isFalse,
        ); // card dropped
        expect(
          lists.left.any((t) => t.type == PanelTypesEnum.room),
          isTrue,
        ); // room kept
        expect(lists.right, [
          const AnalyticsPanelToken(
            AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
          ),
        ]); // kept
      },
    );

    test(
      'closing a course card keeps an open coursepage management page (#7317)',
      () {
        // Closing the master drops only its own token (like the chat list
        // keeping its room); the coursepage child reads on from the surviving
        // ?m= filter, so the edit page must NOT close with the card.
        final loc = WorkspaceNav.closeSection(
          u('/?c=!s&left=course,coursepage:edit'),
          const CoursePanelToken(),
        );
        expect(loc.contains('c='), isTrue); // scope survives
        final lists = parseOpenPanels(u(loc));
        expect(
          lists.left.any((t) => t.type == PanelTypesEnum.course),
          isFalse,
        ); // card gone
        expect(
          lists.left.where((t) => t.type == PanelTypesEnum.coursepage).single,
          CoursePagePanelToken(RoomSubpageTokenParam.parse('edit')),
        ); // edit page kept
      },
    );

    test(
      'closing the course card alone keeps the scoped map, not bare world',
      () {
        final loc = WorkspaceNav.closeSection(
          u('/?c=!s&left=course'),
          const CoursePanelToken(),
        );
        expect(loc.contains('c='), isTrue); // scope survives the close
        expect(
          parseOpenPanels(u(loc)).left,
          isEmpty,
        ); // no panels, just the filter
      },
    );

    test('closing a section with no filter lands on a bare world path', () {
      final loc = WorkspaceNav.closeSection(
        u('/?left=chats'),
        const ChatsPanelToken(),
      );
      expect(loc, '/');
    });

    test('closing the course keeps a launching activity overlay (#7111)', () {
      // A launching/running activity lives in the ?activity= overlay (the center
      // canvas, independent of the course card); closing the course must not
      // drop it.
      final loc = WorkspaceNav.closeSection(
        u('/?c=!s&left=course&activity=act-1&launch=true'),
        const CoursePanelToken(),
      );
      expect(loc.contains('activity=act-1'), isTrue); // overlay preserved
      expect(loc.contains('launch=true'), isTrue);
      expect(loc.contains('c='), isTrue); // scope kept
      expect(
        parseOpenPanels(
          u(loc),
        ).left.any((t) => t.type == PanelTypesEnum.course),
        isFalse,
      ); // card gone
    });
  });

  group('preserveOpenPanels carries the right list, not the left', () {
    test('a section navigation keeps the right panel but drops the left', () {
      // Seed the remembered URL with both lists, then navigate to a new path
      // that names no panels (a bare section nav).
      WorkspaceNav.preserveOpenPanels(
        u('/chats?left=chats,room:!a&right=analytics:vocab'),
      );
      final result = WorkspaceNav.preserveOpenPanels(u('/profile'));
      expect(result, isNotNull);
      final parsed = u(result!);
      expect(parsed.path, '/profile');
      expect(parseOpenPanels(parsed).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
      expect(parseOpenPanels(parsed).left, isEmpty);
    });
  });

  group('clearAll (World/home clears the whole workspace)', () {
    test('returns the bare world map path', () {
      expect(WorkspaceNav.clearAll(), '/');
    });

    test('preserveOpenPanels does not carry companions onto bare home', () {
      // Seed a remembered URL with an open right panel, then go home.
      WorkspaceNav.preserveOpenPanels(
        u('/chats?left=chats&right=analytics:vocab'),
      );
      // Bare home is accepted as-is (null) — not rewritten to re-attach right=.
      expect(WorkspaceNav.preserveOpenPanels(u('/')), isNull);
    });
  });

  group('openSettings / settingsBack (the right-column settings panel)', () {
    test('opens the menu and drops the open analytics panel (#7109)', () {
      final loc = WorkspaceNav.openSettings(u('/?right=analytics:vocab'));
      final right = parseOpenPanels(u(loc)).right;
      expect(
        right.any((t) => t.type == PanelTypesEnum.settings && t.param == null),
        isTrue,
      );
      // Opening Settings closes the analytics panel — symmetric with opening
      // analytics replacing the right column — so they don't clutter it (#7109).
      expect(right.any((t) => t.type == PanelTypesEnum.analytics), isFalse);
    });

    test('opening a settings page drops open vocab/grammar/analytics '
        'details (#7109)', () {
      final loc = WorkspaceNav.openSettings(
        u('/?right=vocab:abc,grammar:def,analytics:vocab'),
        page: 'learning',
      );
      final right = parseOpenPanels(u(loc)).right;
      // Only the settings page + its menu master remain; the analytics family
      // is gone. Master-first: the menu precedes its page.
      expect(right.map((t) => t.type), [
        PanelTypesEnum.settings,
        PanelTypesEnum.settingspage,
      ]);
    });

    test('opening a page seats it as a detail BESIDE the menu master', () {
      final loc = WorkspaceNav.openSettings(u('/'), page: 'learning');
      final right = parseOpenPanels(u(loc)).right;
      // Master-first: the menu comes first, the page detail after it (the
      // renderer blooms the page left of the edge-justified menu).
      expect(right.map((t) => t.type), [
        PanelTypesEnum.settings,
        PanelTypesEnum.settingspage,
      ]);

      final param = right.last.param;
      expect(param, isA<SettingsTokenParam>());
      expect((param as SettingsTokenParam).subpage, 'learning');
    });

    test('opening another page replaces the page detail (one at a time)', () {
      var loc = WorkspaceNav.openSettings(u('/'), page: 'security');
      loc = WorkspaceNav.openSettings(u(loc), page: 'security/password');
      final pages = parseOpenPanels(
        u(loc),
      ).right.where((t) => t.type == PanelTypesEnum.settingspage).toList();
      expect(pages.length, 1);

      final param = pages.single.param;
      expect(param, isA<SettingsTokenParam>());
      expect(
        (param as SettingsTokenParam).subpage,
        'security/password',
      ); // slash survives
      expect(
        parseOpenPanels(
          u(loc),
        ).right.any((t) => t.type == PanelTypesEnum.settings),
        isTrue,
      ); // menu still there
    });

    test('the profile editor is a single-segment leaf, so its back returns to '
        'the menu in one step — not via a phantom profile parent (#7147)', () {
      // The Settings menu opens the editor as `profile`, NOT `profile/edit`.
      // Both render the same editor, so a nested `profile/edit` leaf made the
      // back arrow popPage to an identical-looking `profile` page first,
      // forcing a second click. A single-segment param has no `/`, so the
      // panel treats its back as a plain close that reveals the menu in one
      // step.
      final opened = WorkspaceNav.openSettings(u('/'), page: 'profile');
      final page = parseOpenPanels(
        u(opened),
      ).right.firstWhere((t) => t.type == PanelTypesEnum.settingspage);

      final param = page.param;
      expect(param, isA<SettingsTokenParam>());
      expect(
        (param as SettingsTokenParam).subpage,
        'profile',
      ); // single segment, not 'profile/edit'
      expect(
        param.build().contains('/'),
        isFalse,
      ); // back is a close, not popPage
      // One close drops the page and lands on the menu.
      final back = WorkspaceNav.closeRight(
        u(opened),
        SettingsPagePanelToken(SettingsTokenParam.parse('profile')),
      );
      final right = parseOpenPanels(u(back)).right;
      expect(
        right.any((t) => t.type == PanelTypesEnum.settingspage),
        isFalse,
      ); // page gone
      expect(
        right.single.type,
        PanelTypesEnum.settings,
      ); // menu remains, one step
    });

    test('settingsBack: a leaf pops to its parent page; a top-level page '
        'returns to the menu (drops the page detail)', () {
      final toSecurity = WorkspaceNav.settingsBack(
        u(WorkspaceNav.openSettings(u('/'), page: 'security/password')),
        'security/password',
      );

      final param = parseOpenPanels(
        u(toSecurity),
      ).right.firstWhere((t) => t.type == PanelTypesEnum.settingspage).param;
      expect(param, isA<SettingsTokenParam>());
      expect((param as SettingsTokenParam).subpage, 'security');

      final toMenu = WorkspaceNav.settingsBack(
        u(WorkspaceNav.openSettings(u('/'), page: 'learning')),
        'learning',
      );
      final right = parseOpenPanels(u(toMenu)).right;
      expect(
        right.any((t) => t.type == PanelTypesEnum.settingspage),
        isFalse,
      ); // page gone
      expect(right.single.type, PanelTypesEnum.settings); // menu remains
    });

    test('closeSettings drops only the menu, keeping an open settingspage '
        'detail (#7493)', () {
      // Closing the settings MENU drops only its own token — the same rule
      // closeSection documents for the course family (a coursepage survives
      // its course card closing, #7317). A settingspage reads its own
      // identity from its token param, so it keeps rendering without its
      // master beside it.
      var loc = WorkspaceNav.openSettings(
        u('/?left=room:!a'),
        page: 'learning',
      );
      loc = WorkspaceNav.closeSettings(u(loc));
      final panels = parseOpenPanels(u(loc));
      expect(
        panels.right.any((t) => t.type == PanelTypesEnum.settings),
        isFalse,
      );
      expect(
        panels.right.single,
        const SettingsPagePanelToken(SettingsTokenParam(subpage: 'learning')),
      ); // page survives
      expect(
        panels.left.single,
        const RoomPanelToken(RoomTokenParam(id: '!a')),
      );
    });

    test(
      'closeSettings on a bare menu (no open page) clears the right column',
      () {
        // Analytics can no longer coexist with settings (opening settings
        // drops it, #7109), so with no settingspage open, closing the menu
        // leaves the right column empty.
        var loc = WorkspaceNav.openSettings(u('/?left=room:!a'));
        loc = WorkspaceNav.closeSettings(u(loc));
        final panels = parseOpenPanels(u(loc));
        expect(panels.right, isEmpty);
        expect(
          panels.left.single,
          const RoomPanelToken(RoomTokenParam(id: '!a')),
        );
      },
    );

    test('closing the settingspage detail keeps the settings menu master', () {
      // The reverse case: closing the page (via closeRight, the page's own
      // close) must not touch the menu — mirrored to the course family's
      // coursepage close.
      final loc = WorkspaceNav.openSettings(u('/'), page: 'learning');
      final closed = WorkspaceNav.closeRight(
        u(loc),
        const SettingsPagePanelToken(SettingsTokenParam(subpage: 'learning')),
      );
      final panels = parseOpenPanels(u(closed));
      expect(
        panels.right.any((t) => t.type == PanelTypesEnum.settingspage),
        isFalse,
      );
      expect(panels.right.single.type, PanelTypesEnum.settings); // menu remains
    });
  });

  group('setSection (move between sections, keep the live chat)', () {
    test('moving to the world keeps the live room and the right column', () {
      final world = WorkspaceNav.setSection(
        u('/chats?left=chats,room:!a&right=analytics:vocab'),
        null,
      );
      expect(u(world).path, '/');
      final lists = parseOpenPanels(u(world));
      expect(lists.left, [
        RoomPanelToken(RoomTokenParam.parse('!a')),
      ]); // room kept, no section
      expect(lists.right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]); // kept
    });

    test('sets the new section in front of the kept room', () {
      // setSection always emits the world path `/` — section identity rides
      // in the token, never a path segment.
      final chats = WorkspaceNav.setSection(
        u('/?left=room:!a&right=analytics:vocab'),
        const ChatsPanelToken(),
      );
      expect(u(chats).path, '/');
      expect(parseOpenPanels(u(chats)).left, [
        const ChatsPanelToken(),
        RoomPanelToken(RoomTokenParam.parse('!a')),
      ]);
    });

    test('keepRoom:false drops the room (focused full-bleed flow)', () {
      final hub = WorkspaceNav.setSection(
        u('/chats?left=chats,room:!a&right=analytics:vocab'),
        null,
        keepRoom: false,
      );
      expect(parseOpenPanels(u(hub)).left, isEmpty);
      expect(parseOpenPanels(u(hub)).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
    });

    test('carries the map filter forward (scope survives a section switch)', () {
      // Switching to a non-map section (chats) keeps the course scope — only a
      // new focus (a course) or the World control changes `?m=`.
      final chats = WorkspaceNav.setSection(
        u('/?c=!s&left=course&right=analytics:vocab'),
        const ChatsPanelToken(),
        keepRoom: false,
      );
      expect(chats.contains('c='), isTrue);
      final lists = parseOpenPanels(u(chats));
      expect(lists.left, [const ChatsPanelToken()]); // section replaced left
      expect(lists.right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]); // kept
    });

    test('back from the route-driven course detail lands on the plan list '
        '(#7090)', () {
      // The course detail is route-driven (`/courses/own/:courseid`), so its
      // parent segments render a blank EmptyPage. Its back navigates to the
      // start-my-own plan list token over the world map rather than popping to
      // that blank parent — even though the current URL is the legacy path.
      final planList = WorkspaceNav.setSection(
        u('/courses/own/abc-123'),
        AddCoursePagePanelToken(AddCoursePageTokenParam.parse('own')),
        keepRoom: false,
      );
      expect(u(planList).path, '/');
      expect(parseOpenPanels(u(planList)).left, [
        AddCoursePagePanelToken(AddCoursePageTokenParam.parse('own')),
      ]);
      expect(parseOpenPanels(u(planList)).right, isEmpty);
    });

    test('back from the route-driven public course preview lands on the '
        'browse-public list (#7400)', () {
      // The public course preview is route-driven
      // (`/courses/preview/:courseroomid`), so its parent segments render a
      // blank EmptyPage. `PublicCoursePreviewController.back` navigates to the
      // browse-public list token over the world map rather than popping to that
      // blank parent — even though the current URL is the legacy preview path.
      final browseList = WorkspaceNav.setSection(
        u('/courses/preview/!abc:server'),
        AddCoursePagePanelToken(AddCoursePageTokenParam.parse('browse')),
        keepRoom: false,
      );
      expect(u(browseList).path, '/');
      expect(parseOpenPanels(u(browseList)).left, [
        AddCoursePagePanelToken(AddCoursePageTokenParam.parse('browse')),
      ]);
      expect(parseOpenPanels(u(browseList)).right, isEmpty);
    });
  });

  group('openDetail (generic, registry-driven exclusive groups)', () {
    test(
      'a left room drops other room/session (liveView) but keeps the right',
      () {
        final constructId = ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.vocab,
          'a',
        );
        var loc = WorkspaceNav.openConstructDetail(
          u('/'),
          ConstructTypeEnum.vocab,
          constructId: constructId,
        );
        loc = WorkspaceNav.openExclusiveLeftRoom(
          u(loc),
          RoomPanelToken(RoomTokenParam.parse('!a')),
        );
        loc = WorkspaceNav.openDetail(
          u(loc),
          RoomPanelToken(RoomTokenParam.parse('!b')),
        );
        final lists = parseOpenPanels(u(loc));
        expect(
          lists.left
              .where((t) => t.type == PanelTypesEnum.room)
              .map((t) => t.param)
              .whereType<RoomTokenParam>()
              .map((r) => r.id)
              .toList(),
          ['!b'],
        );
        // vocab is `detail`, room is `liveView` — no shared group, so it survives.
        expect(lists.right.any((t) => t.type == PanelTypesEnum.vocab), isTrue);
      },
    );

    test(
      'a session (liveView+detail) drops both a room AND a vocab detail',
      () {
        final constructId = ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.vocab,
          'a',
        );
        var loc = WorkspaceNav.openConstructDetail(
          u('/'),
          ConstructTypeEnum.vocab,
          constructId: constructId,
        );
        loc = WorkspaceNav.openExclusiveLeftRoom(
          u(loc),
          RoomPanelToken(RoomTokenParam.parse('!a')),
        );
        loc = WorkspaceNav.openDetail(
          u(loc),
          SessionPanelToken(RoomTokenParam.parse('!s')),
        );
        final lists = parseOpenPanels(u(loc));
        expect(lists.left.where((t) => t.type == PanelTypesEnum.room), isEmpty);
        expect(
          lists.left.single,
          SessionPanelToken(RoomTokenParam.parse('!s')),
        );
        expect(
          lists.right.any(
            (t) =>
                t.type == PanelTypesEnum.vocab ||
                t.type == PanelTypesEnum.grammar,
          ),
          isFalse,
        );
      },
    );
  });

  group('inbound join-code consumption (#7524)', () {
    // The auto-submit's history REPLACE target: the coded `private/<code>`
    // leaf reduced to the manual `private` page, so browser back / refresh
    // never re-fires the join (course_code_page.dart).
    test('replacing the coded leaf with the manual page strips the code', () {
      final coded = u('/?left=addcoursepage:private.jvj3pc8b');
      expect(joinCodeFor(coded), 'vj3pc8b');
      final consumed = WorkspaceNav.pushPage(
        coded,
        AddCoursePagePanelToken(
          AddCoursePageTokenParam(subpage: AddCourseSubpageEnum.private),
        ),
      );
      expect(consumed, '/?left=addcoursepage:private');
      expect(joinCodeFor(u(consumed)), isNull);
    });

    test('consumption preserves the rest of the workspace URL', () {
      final coded = u(
        '/?c=!s&left=addcoursepage:private%2Fvj3pc8b&right=analytics:vocab',
      );
      final consumed = u(
        WorkspaceNav.pushPage(
          coded,
          AddCoursePagePanelToken(
            AddCoursePageTokenParam(subpage: AddCourseSubpageEnum.private),
          ),
        ),
      );
      expect(joinCodeFor(consumed), isNull);
      expect(activeSpaceIdFor(consumed), isNotNull);
      expect(parseOpenPanels(consumed).right, [
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ]);
      expect(parseOpenPanels(consumed).left, [
        const AddCoursePagePanelToken(
          AddCoursePageTokenParam(subpage: AddCourseSubpageEnum.private),
        ),
      ]);
    });
  });

  group('pushPage / popPage (generic param push on a pushable panel)', () {
    test('push deepens the param; pop returns one level then to the root', () {
      var loc = WorkspaceNav.pushPage(
        u('/'),
        SettingsPagePanelToken(SettingsTokenParam.parse('security')),
      );
      expect(
        parseOpenPanels(u(loc)).right.single,
        SettingsPagePanelToken(SettingsTokenParam.parse('security')),
      );
      loc = WorkspaceNav.pushPage(
        u(loc),
        SettingsPagePanelToken(SettingsTokenParam.parse('security/password')),
      );
      expect(
        parseOpenPanels(u(loc)).right.single,
        SettingsPagePanelToken(SettingsTokenParam.parse('security/password')),
      );
      loc = WorkspaceNav.popPage(
        u(loc),
        SettingsPagePanelToken(SettingsTokenParam.parse('security/password')),
      );
      expect(
        parseOpenPanels(u(loc)).right.single,
        SettingsPagePanelToken(SettingsTokenParam.parse('security')),
      );
      loc = WorkspaceNav.popPage(
        u(loc),
        SettingsPagePanelToken(SettingsTokenParam.parse('security')),
      );
      expect(parseOpenPanels(u(loc)).right.length, 0);
    });

    test('pushing keeps other panels in the column', () {
      var loc = WorkspaceNav.openRight(
        u('/'),
        const AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      );
      loc = WorkspaceNav.pushPage(
        u(loc),
        SettingsPagePanelToken(SettingsTokenParam.parse('learning')),
      );
      final right = parseOpenPanels(u(loc)).right.map((t) => t.type).toSet();
      expect(
        right.containsAll({
          PanelTypesEnum.analytics,
          PanelTypesEnum.settingspage,
        }),
        isTrue,
      );
    });

    test('a course management page opens beside the card as a coursepage '
        'detail, keeping the map filter; one at a time; closing reveals the '
        'card', () {
      // The course workspace: a `?m=course:<id>` map filter + a left course
      // panel. A management button (Edit, Invite, …) opens beside the card.
      const base = '/?c=!s&left=course';
      var loc = WorkspaceNav.openCoursePage(u(base), RoomSubpageEnum.edit);
      final left = parseOpenPanels(u(loc)).left;
      expect(left.map((t) => t.type).toList(), [
        PanelTypesEnum.course,
        PanelTypesEnum.coursepage,
      ]);
      expect(
        left.last,
        CoursePagePanelToken(RoomSubpageTokenParam.parse('edit')),
      );
      // The course identity (the map filter) survives.
      expect(activeSpaceIdFor(u(loc)), '!s');
      // Opening a different management page replaces the first (one at a time).
      loc = WorkspaceNav.openCoursePage(u(loc), RoomSubpageEnum.invite);
      expect(
        parseOpenPanels(
          u(loc),
        ).left.where((t) => t.type == PanelTypesEnum.coursepage).single,
        CoursePagePanelToken(RoomSubpageTokenParam.parse('invite')),
      );
      // Closing the management detail drops it, leaving the card and filter.
      loc = WorkspaceNav.closeLeft(
        u(loc),
        CoursePagePanelToken(RoomSubpageTokenParam.parse('invite')),
      );
      expect(parseOpenPanels(u(loc)).left.single, const CoursePanelToken());
      expect(activeSpaceIdFor(u(loc)), '!s');
    });

    test('openCoursePage(filter:) folds the invite contact filter into the '
        'coursepage token param instead of a loose ?filter= query', () {
      final loc = WorkspaceNav.openCoursePage(
        u('/?c=!s&left=course'),
        RoomSubpageEnum.invite,
        filter: InvitationFilter.knocking,
      );
      final uri = u(loc);
      expect(uri.queryParameters['filter'], isNull);
      expect(
        parseOpenPanels(
          uri,
        ).left.where((t) => t.type == PanelTypesEnum.coursepage).single,
        CoursePagePanelToken(
          RoomSubpageTokenParam(
            subpage: RoomSubpageEnum.invite,
            inviteFilter: InvitationFilter.knocking,
          ),
        ),
      );
    });

    test(
      'openCoursePageFor opens a management page from ANYWHERE — setting the '
      'target space scope even from the bare map or a different course',
      () {
        // From the bare world map (no course scope at all).
        var loc = WorkspaceNav.openCoursePageFor(
          u('/'),
          '!target',
          RoomSubpageEnum.invite,
        );
        expect(activeSpaceIdFor(u(loc)), '!target');
        expect(parseOpenPanels(u(loc)).left.map((t) => t.type).toList(), [
          PanelTypesEnum.course,
          PanelTypesEnum.coursepage,
        ]);
        expect(
          parseOpenPanels(u(loc)).left.last,
          CoursePagePanelToken(RoomSubpageTokenParam.parse('invite')),
        );
        // From a DIFFERENT course — the scope is replaced with the target's.
        loc = WorkspaceNav.openCoursePageFor(
          u('/?c=!other&left=course'),
          '!target',
          RoomSubpageEnum.edit,
        );
        expect(activeSpaceIdFor(u(loc)), '!target');
        expect(
          parseOpenPanels(
            u(loc),
          ).left.where((t) => t.type == PanelTypesEnum.coursepage).single,
          CoursePagePanelToken(RoomSubpageTokenParam.parse('edit')),
        );
      },
    );
  });

  group('openPractice (takes over the analytics surface)', () {
    test(
      'clears the analytics master + vocab/grammar details + a left session, '
      'then seats practice',
      () {
        const base =
            '/?left=room:!r,session:!s&right=vocab:a.adj,analytics:vocab';
        final loc = WorkspaceNav.openPractice(u(base), ConstructTypeEnum.vocab);
        final lists = parseOpenPanels(u(loc));
        // The right column is just the practice panel — analytics + vocab gone.
        expect(
          lists.right.single,
          AnalyticsPracticePanelToken(
            AnalyticsPracticeTokenParam.parse('vocab'),
          ),
        );
        // The left session (shares the detail slot) is dropped; the live room
        // (independent) stays.
        expect(lists.left.map((t) => t.type), [PanelTypesEnum.room]);
      },
    );

    test(
      'opening a construct detail closes practice (one detail across columns)',
      () {
        final practice = WorkspaceNav.openPractice(
          u('/'),
          ConstructTypeEnum.vocab,
        );
        expect(
          parseOpenPanels(u(practice)).right.single,
          AnalyticsPracticePanelToken(
            AnalyticsPracticeTokenParam.parse('vocab'),
          ),
        );
        final param = VocabAnalyticsTokenParam.parse('{"l":"x"}');
        final loc = WorkspaceNav.openConstructDetail(
          u(practice),
          ConstructTypeEnum.vocab,
          constructId: param.constructId,
        );
        final right = parseOpenPanels(u(loc)).right;
        // practice is gone; the vocab detail + its analytics master are seated.
        expect(right.any((t) => t.type == PanelTypesEnum.practice), isFalse);
        expect(right.map((t) => t.type).toSet(), {
          PanelTypesEnum.vocab,
          PanelTypesEnum.analytics,
        });
      },
    );
  });

  group('openCourseActivity (token-native activity panel, #7385/#7267)', () {
    // Bare localpart ids (no `:domain`): shortRoomId only strips the home
    // server_name, which is unavailable in a unit test (no MatrixState), so a
    // `!x:server.com` would ride the URL whole. The existing course helpers test
    // the same way — the id format is orthogonal to what this producer asserts.
    test('sets the course context + a sole `left=activity:` token — no other '
        'left/right panels (#7385 first-class panel, #7267 split)', () {
      final loc = WorkspaceNav.openCourseActivity('!space', 'act-123');
      final uri = u(loc);
      expect(uri.path, '/'); // over the persistent world map
      // The `c=` param is the course context, read by map and panels alike.
      expect(activeSpaceIdFor(uri), '!space');
      // #7385: the activity is a first-class left panel token (claims the
      // single live view), not the old `?activity=` canvas overlay; its id
      // rides the token's fields.
      expect(activityInfoFor(uri)?.activityId, 'act-123');
      expect(uri.queryParameters['activity'], isNull);
      // #7267: the activity REPLACES the panels, so no `left=course` card rides
      // beside it and no right panel survives.
      expect(WorkspaceQuery.valueOf(uri.query, 'right'), isNull);
      expect(parseOpenPanels(uri).left.map((t) => t.type), [
        PanelTypesEnum.activity,
      ]);
    });

    test('launch:true rides the token fields, never a loose param', () {
      final loc = WorkspaceNav.openCourseActivity(
        '!space',
        'act-123',
        launch: true,
      );
      final uri = u(loc);
      expect(activityInfoFor(uri)?.launch, isTrue);
      expect(uri.queryParameters['launch'], isNull);
    });

    test('roomId binds the session room in the token fields', () {
      final loc = WorkspaceNav.openCourseActivity(
        '!space',
        'act-123',
        roomId: '!sess',
      );
      final uri = u(loc);
      expect(activityInfoFor(uri)?.roomId, '!sess');
      expect(uri.queryParameters['roomid'], isNull);
    });

    test(
      'autoplay:true autostarts the hero media at block 0 (token field)',
      () {
        final loc = WorkspaceNav.openCourseActivity(
          '!space',
          'act-123',
          autoplay: true,
        );
        final uri = u(loc);
        expect(activityInfoFor(uri)?.autoplay, 0);
        expect(uri.queryParameters['autoplay'], isNull);
      },
    );
  });
}
