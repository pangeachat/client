import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';

void main() {
  Uri u(String s) => Uri.parse(s);

  group('openRight / closeRight', () {
    test('adds a token and round-trips back through the parser', () {
      final loc = WorkspaceNav.openRight(
        u('/chats'),
        const PanelToken('analytics', '!def'),
      );
      expect(parseOpenPanels(u(loc)).right, [
        const PanelToken('analytics', '!def'),
      ]);
    });

    test('an encoded construct param survives the add → URL → parse '
        'round-trip', () {
      const token = PanelToken('vocab', 'a%2Cb.verb');
      final loc = WorkspaceNav.openRight(u('/chats'), token);
      expect(parseOpenPanels(u(loc)).right.single, token);
    });

    test('the parser yields master-first regardless of raw insertion order', () {
      // atStart is a raw list insert, but the parser normalizes a registry
      // master/detail pair to master-first, so the summary always precedes its
      // detail in the URL; the renderer blooms the detail left of the edge.
      var loc = WorkspaceNav.openRight(
        u('/chats'),
        const PanelToken('analytics', 'vocab'),
      );
      loc = WorkspaceNav.openRight(
        u(loc),
        const PanelToken('vocab', 'hablar'),
        atStart: true,
      );
      expect(parseOpenPanels(u(loc)).right.map((t) => t.type), [
        'analytics',
        'vocab',
      ]);
    });

    test('adding an existing token is idempotent (deduped)', () {
      var loc = WorkspaceNav.openRight(
        u('/chats'),
        const PanelToken('analytics', '!a'),
      );
      loc = WorkspaceNav.openRight(u(loc), const PanelToken('analytics', '!a'));
      expect(parseOpenPanels(u(loc)).right.length, 1);
    });

    test(
      'close removes the token; the key disappears when the list empties',
      () {
        final opened = WorkspaceNav.openRight(
          u('/chats'),
          const PanelToken('analytics', '!a'),
        );
        final closed = WorkspaceNav.closeRight(
          u(opened),
          const PanelToken('analytics', '!a'),
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
        const PanelToken('analytics', 'sessions'),
      );
      final parsed = u(loc);
      expect(parsed.queryParameters['activity'], 'abc');
      expect(parseOpenPanels(parsed).right, [
        const PanelToken('analytics', 'sessions'),
      ]);
      expect(parsed.path, '/courses/!s');
    });

    test('the path is preserved', () {
      final loc = WorkspaceNav.openRight(
        u('/rooms/!abc'),
        const PanelToken('analytics', '!def'),
      );
      expect(u(loc).path, '/rooms/!abc');
    });
  });

  group('setRight replaces the whole list (metric switch)', () {
    test('drops the old analytics/detail tokens and seats one summary', () {
      var loc = WorkspaceNav.openRight(
        u('/chats'),
        const PanelToken('analytics', 'vocab'),
      );
      loc = WorkspaceNav.openRight(
        u(loc),
        const PanelToken('vocab', 'hablar'),
        atStart: true,
      );
      loc = WorkspaceNav.setRight(u(loc), [
        const PanelToken('analytics', 'grammar'),
      ]);
      expect(parseOpenPanels(u(loc)).right, [
        const PanelToken('analytics', 'grammar'),
      ]);
    });
  });

  group('openRoomById (event folds into the room token; no loose params)', () {
    test('a bare call opens the room with no event/body query at all', () {
      final loc = WorkspaceNav.openRoomById(u('/chats'), '!abc');
      final uri = u(loc);
      expect(parseOpenPanels(uri).left, [const PanelToken('room', '!abc')]);
      expect(uri.queryParameters['event'], isNull);
      expect(uri.queryParameters['body'], isNull);
    });

    test('event rides the room token param, not a loose ?event= query', () {
      final loc = WorkspaceNav.openRoomById(u('/chats'), '!abc', event: r'$e1');
      final uri = u(loc);
      expect(uri.queryParameters['event'], isNull);
      final room = parseOpenPanels(uri).left.single;
      expect(RoomToken.parse(room.param!).eventId, r'$e1');
    });

    test('subPage still pushes normally alongside a room open', () {
      final loc = WorkspaceNav.openRoomById(
        u('/chats'),
        '!abc',
        subPage: 'details',
      );
      final room = parseOpenPanels(u(loc)).left.single;
      expect(room.param, '!abc/details');
    });
  });

  group('openExclusiveLeftRoom (one live session)', () {
    test('opening a room drops any other room but keeps chats/course', () {
      var loc = WorkspaceNav.setLeft(u('/chats'), const [
        PanelToken('chats'),
        PanelToken('room', '!a'),
      ]);
      loc = WorkspaceNav.openExclusiveLeftRoom(
        u(loc),
        const PanelToken('room', '!b'),
      );
      final left = parseOpenPanels(u(loc)).left;
      expect(left.where((t) => t.type == 'room').map((t) => t.param).toList(), [
        '!b',
      ]);
      expect(left.any((t) => t.type == 'chats'), isTrue);
    });

    test('preserves an open right panel by construction', () {
      final loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/chats?right=analytics:vocab'),
        const PanelToken('room', '!a'),
      );
      expect(parseOpenPanels(u(loc)).right, [
        const PanelToken('analytics', 'vocab'),
      ]);
    });
  });

  group('openCourse (open / switch tab)', () {
    test('switching tabs replaces the course token rather than stacking', () {
      // The course id lives in the `?m=course:` map filter; the token param is
      // just the tab (a bare course token with no filter is dropped at parse).
      var loc = WorkspaceNav.openCourse(
        u('/?c=!s'),
        const PanelToken('course', 'chat'),
      );
      loc = WorkspaceNav.openCourse(
        u(loc),
        const PanelToken('course', 'participants'),
      );
      final courses = parseOpenPanels(
        u(loc),
      ).left.where((t) => t.type == 'course').toList();
      expect(courses.length, 1);
      expect(courses.single.param, 'participants');
    });

    test('keeps a live room beside the course (a course can scope a room)', () {
      // A course-scoped room: the `?m=course:` filter is set, the room is live,
      // and opening the course card keeps the room beside it.
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/?c=!s'),
        const PanelToken('room', '!a'),
      );
      loc = WorkspaceNav.openCourse(u(loc), const PanelToken('course'));
      final left = parseOpenPanels(u(loc)).left;
      expect(left.any((t) => t.type == 'room'), isTrue);
      expect(left.any((t) => t.type == 'course'), isTrue);
    });

    test('reopening the course card sheds an open immersive activity (#7385)', () {
      // The in-course "Pick different activity" / "Return to course" exits route
      // through openCourse/openCourseFilter: showing the card is leaving the
      // activity, so the live-view activity token must NOT co-render beside it
      // (it is not a sibling of `course`, so only an explicit drop clears it).
      final fromActivity = u('/?c=!s&left=activity:abc');
      final viaOpenCourse = parseOpenPanels(
        u(WorkspaceNav.openCourse(fromActivity, const PanelToken('course'))),
      ).left;
      expect(viaOpenCourse.any((t) => t.type == 'activity'), isFalse);
      expect(viaOpenCourse.any((t) => t.type == 'course'), isTrue);

      final viaFilter = parseOpenPanels(
        u(WorkspaceNav.openCourseFilter(fromActivity, '!s', tab: 'course')),
      ).left;
      expect(viaFilter.any((t) => t.type == 'activity'), isFalse);
      expect(viaFilter.any((t) => t.type == 'course'), isTrue);
    });
  });

  group('openConstructDetail (one detail at a time, across columns)', () {
    test(
      'a new construct detail replaces the prior one, keeping the summary',
      () {
        var loc = WorkspaceNav.openRight(
          u('/'),
          const PanelToken('analytics', 'vocab'),
        );
        loc = WorkspaceNav.openConstructDetail(
          u(loc),
          const PanelToken('vocab', 'hablar'),
          'vocab',
        );
        loc = WorkspaceNav.openConstructDetail(
          u(loc),
          const PanelToken('grammar', 'verb'),
          'grammar',
        );
        final right = parseOpenPanels(u(loc)).right;
        // exactly one construct detail, blooming left of its kept summary
        expect(
          right.where((t) => t.type == 'vocab' || t.type == 'grammar').length,
          1,
        );
        expect(
          right.last,
          const PanelToken('grammar', 'verb'),
        ); // detail after its master (master-first; renderer blooms it left)
        expect(right.first.type, 'analytics'); // summary master, kept + first
      },
    );

    test('cold start seats the detail AND its summary together', () {
      final loc = WorkspaceNav.openConstructDetail(
        u('/'),
        const PanelToken('vocab', 'hablar'),
        'vocab',
      );
      final right = parseOpenPanels(u(loc)).right;
      expect(right.map((t) => t.type), ['analytics', 'vocab']); // master-first
      expect(right.first.param, 'vocab'); // the seated summary's tab
    });

    test('opening a construct detail closes an open activity session', () {
      // session (left) + a vocab detail open: drilling a new construct drops the
      // session — one detail at a time across columns.
      var loc = WorkspaceNav.openExclusiveSession(
        u('/'),
        const PanelToken('session', '!s'),
      );
      loc = WorkspaceNav.openConstructDetail(
        u(loc),
        const PanelToken('vocab', 'hablar'),
        'vocab',
      );
      final lists = parseOpenPanels(u(loc));
      expect(
        lists.left.any((t) => t.type == 'session'),
        isFalse,
      ); // session gone
      expect(lists.right.last, const PanelToken('vocab', 'hablar'));
    });

    test('a live room chat is NOT closed by opening a construct detail', () {
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/'),
        const PanelToken('room', '!live'),
      );
      loc = WorkspaceNav.openConstructDetail(
        u(loc),
        const PanelToken('vocab', 'hablar'),
        'vocab',
      );
      final lists = parseOpenPanels(u(loc));
      expect(lists.left.any((t) => t.type == 'room'), isTrue); // chat survives
      expect(lists.right.last, const PanelToken('vocab', 'hablar'));
    });
  });

  group('openExclusiveSession (the session shares the detail slot)', () {
    test('opening a session drops an open vocab/grammar detail', () {
      var loc = WorkspaceNav.openConstructDetail(
        u('/'),
        const PanelToken('vocab', 'hablar'),
        'vocab',
      );
      loc = WorkspaceNav.openExclusiveSession(
        u(loc),
        const PanelToken('session', '!s'),
      );
      final lists = parseOpenPanels(u(loc));
      expect(
        lists.right.any((t) => t.type == 'vocab' || t.type == 'grammar'),
        isFalse,
      ); // construct detail gone
      expect(lists.left.any((t) => t.type == 'session'), isTrue);
    });

    test('a session drops another room/session (one live view)', () {
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/'),
        const PanelToken('room', '!live'),
      );
      loc = WorkspaceNav.openExclusiveSession(
        u(loc),
        const PanelToken('session', '!s'),
      );
      final left = parseOpenPanels(u(loc)).left;
      expect(
        left.where((t) => t.type == 'room' || t.type == 'session').length,
        1,
      );
      expect(left.single, const PanelToken('session', '!s'));
    });

    test('opening a session from Stars closes the open course card (#7106)', () {
      // A saved activity opened from the Stars archive takes over the left
      // column: the open course card closes (so the review isn't rendered behind
      // it) while the map scope is kept.
      final loc = WorkspaceNav.openExclusiveSession(
        u('/?c=!s&left=course'),
        const PanelToken('session', '!a'),
      );
      final left = parseOpenPanels(u(loc)).left;
      expect(left.any((t) => t.type == 'course'), isFalse); // card closed
      expect(left.singleWhere((t) => t.type == 'session').param, '!a');
      expect(loc.contains('c='), isTrue); // map scope preserved
    });
  });

  group('setLeft / clearLeft', () {
    test('setLeft replaces the whole left list, preserving right', () {
      var loc = WorkspaceNav.setLeft(u('/chats?right=analytics:vocab'), const [
        PanelToken('room', '!a'),
        PanelToken('chats'),
      ]);
      // Replace with a filter-independent left root (a bare course would be
      // dropped at parse for lacking its `?m=course:` filter).
      loc = WorkspaceNav.setLeft(u(loc), const [PanelToken('addcourse')]);
      expect(parseOpenPanels(u(loc)).left, [const PanelToken('addcourse')]);
      expect(parseOpenPanels(u(loc)).right, [
        const PanelToken('analytics', 'vocab'),
      ]);
    });

    test('clearLeft empties the left list but keeps right', () {
      final loc = WorkspaceNav.clearLeft(
        u('/chats?left=chats&right=analytics:vocab'),
      );
      expect(parseOpenPanels(u(loc)).left, isEmpty);
      expect(parseOpenPanels(u(loc)).right, [
        const PanelToken('analytics', 'vocab'),
      ]);
    });
  });

  group('closeSection (drop a section panel, keep the map filter)', () {
    test(
      'closing a course card keeps its ?m= filter, the room, and the right',
      () {
        final loc = WorkspaceNav.closeSection(
          u('/?c=!s&left=course,room:!a&right=analytics:vocab'),
          const PanelToken('course'),
        );
        // Scope is independent of panels: the map stays course-scoped (filter
        // survives), the card is gone, the room and right column are kept.
        expect(loc.contains('c='), isTrue);
        final lists = parseOpenPanels(u(loc));
        expect(
          lists.left.any((t) => t.type == 'course'),
          isFalse,
        ); // card dropped
        expect(lists.left.any((t) => t.type == 'room'), isTrue); // room kept
        expect(lists.right, [const PanelToken('analytics', 'vocab')]); // kept
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
          const PanelToken('course'),
        );
        expect(loc.contains('c='), isTrue); // scope survives
        final lists = parseOpenPanels(u(loc));
        expect(lists.left.any((t) => t.type == 'course'), isFalse); // card gone
        expect(
          lists.left.where((t) => t.type == 'coursepage').single,
          const PanelToken('coursepage', 'edit'),
        ); // edit page kept
      },
    );

    test(
      'closing the course card alone keeps the scoped map, not bare world',
      () {
        final loc = WorkspaceNav.closeSection(
          u('/?c=!s&left=course'),
          const PanelToken('course'),
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
        const PanelToken('chats'),
      );
      expect(loc, '/');
    });

    test('closing the course keeps a launching activity overlay (#7111)', () {
      // A launching/running activity lives in the ?activity= overlay (the center
      // canvas, independent of the course card); closing the course must not
      // drop it.
      final loc = WorkspaceNav.closeSection(
        u('/?c=!s&left=course&activity=act-1&launch=true'),
        const PanelToken('course'),
      );
      expect(loc.contains('activity=act-1'), isTrue); // overlay preserved
      expect(loc.contains('launch=true'), isTrue);
      expect(loc.contains('c='), isTrue); // scope kept
      expect(
        parseOpenPanels(u(loc)).left.any((t) => t.type == 'course'),
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
        const PanelToken('analytics', 'vocab'),
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
      expect(right.any((t) => t.type == 'settings' && t.param == null), isTrue);
      // Opening Settings closes the analytics panel — symmetric with opening
      // analytics replacing the right column — so they don't clutter it (#7109).
      expect(right.any((t) => t.type == 'analytics'), isFalse);
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
      expect(right.map((t) => t.type), ['settings', 'settingspage']);
    });

    test('opening a page seats it as a detail BESIDE the menu master', () {
      final loc = WorkspaceNav.openSettings(u('/'), page: 'learning');
      final right = parseOpenPanels(u(loc)).right;
      // Master-first: the menu comes first, the page detail after it (the
      // renderer blooms the page left of the edge-justified menu).
      expect(right.map((t) => t.type), ['settings', 'settingspage']);
      expect(right.last.param, 'learning');
    });

    test('opening another page replaces the page detail (one at a time)', () {
      var loc = WorkspaceNav.openSettings(u('/'), page: 'security');
      loc = WorkspaceNav.openSettings(u(loc), page: 'security/password');
      final pages = parseOpenPanels(
        u(loc),
      ).right.where((t) => t.type == 'settingspage').toList();
      expect(pages.length, 1);
      expect(pages.single.param, 'security/password'); // slash survives
      expect(
        parseOpenPanels(u(loc)).right.any((t) => t.type == 'settings'),
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
      ).right.firstWhere((t) => t.type == 'settingspage');
      expect(page.param, 'profile'); // single segment, not 'profile/edit'
      expect(
        page.param!.contains('/'),
        isFalse,
      ); // back is a close, not popPage
      // One close drops the page and lands on the menu.
      final back = WorkspaceNav.closeRight(
        u(opened),
        const PanelToken('settingspage', 'profile'),
      );
      final right = parseOpenPanels(u(back)).right;
      expect(right.any((t) => t.type == 'settingspage'), isFalse); // page gone
      expect(right.single.type, 'settings'); // menu remains, one step
    });

    test('settingsBack: a leaf pops to its parent page; a top-level page '
        'returns to the menu (drops the page detail)', () {
      final toSecurity = WorkspaceNav.settingsBack(
        u(WorkspaceNav.openSettings(u('/'), page: 'security/password')),
        'security/password',
      );
      expect(
        parseOpenPanels(
          u(toSecurity),
        ).right.firstWhere((t) => t.type == 'settingspage').param,
        'security',
      );
      final toMenu = WorkspaceNav.settingsBack(
        u(WorkspaceNav.openSettings(u('/'), page: 'learning')),
        'learning',
      );
      final right = parseOpenPanels(u(toMenu)).right;
      expect(right.any((t) => t.type == 'settingspage'), isFalse); // page gone
      expect(right.single.type, 'settings'); // menu remains
    });

    test('closeSettings drops the menu AND its page, keeps the rest', () {
      // Analytics can no longer coexist with settings (opening settings drops
      // it, #7109), so "the rest" is a left panel. closeSettings clears the
      // right settings panel and leaves the left column intact.
      var loc = WorkspaceNav.openSettings(
        u('/?left=room:!a'),
        page: 'learning',
      );
      loc = WorkspaceNav.closeSettings(u(loc));
      final panels = parseOpenPanels(u(loc));
      expect(
        panels.right.any(
          (t) => t.type == 'settings' || t.type == 'settingspage',
        ),
        isFalse,
      );
      expect(panels.left.single, const PanelToken('room', '!a'));
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
        const PanelToken('room', '!a'),
      ]); // room kept, no section
      expect(lists.right, [const PanelToken('analytics', 'vocab')]); // kept
    });

    test('sets the new section in front of the kept room', () {
      // setSection always emits the world path `/` — section identity rides
      // in the token, never a path segment.
      final chats = WorkspaceNav.setSection(
        u('/?left=room:!a&right=analytics:vocab'),
        const PanelToken('chats'),
      );
      expect(u(chats).path, '/');
      expect(parseOpenPanels(u(chats)).left, [
        const PanelToken('chats'),
        const PanelToken('room', '!a'),
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
        const PanelToken('analytics', 'vocab'),
      ]);
    });

    test('carries the map filter forward (scope survives a section switch)', () {
      // Switching to a non-map section (chats) keeps the course scope — only a
      // new focus (a course) or the World control changes `?m=`.
      final chats = WorkspaceNav.setSection(
        u('/?c=!s&left=course&right=analytics:vocab'),
        const PanelToken('chats'),
        keepRoom: false,
      );
      expect(chats.contains('c='), isTrue);
      final lists = parseOpenPanels(u(chats));
      expect(lists.left, [const PanelToken('chats')]); // section replaced left
      expect(lists.right, [const PanelToken('analytics', 'vocab')]); // kept
    });

    test('back from the route-driven course detail lands on the plan list '
        '(#7090)', () {
      // The course detail is route-driven (`/courses/own/:courseid`), so its
      // parent segments render a blank EmptyPage. Its back navigates to the
      // start-my-own plan list token over the world map rather than popping to
      // that blank parent — even though the current URL is the legacy path.
      final planList = WorkspaceNav.setSection(
        u('/courses/own/abc-123'),
        const PanelToken('addcourse', 'own'),
        keepRoom: false,
      );
      expect(u(planList).path, '/');
      expect(parseOpenPanels(u(planList)).left, [
        const PanelToken('addcourse', 'own'),
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
        const PanelToken('addcourse', 'browse'),
        keepRoom: false,
      );
      expect(u(browseList).path, '/');
      expect(parseOpenPanels(u(browseList)).left, [
        const PanelToken('addcourse', 'browse'),
      ]);
      expect(parseOpenPanels(u(browseList)).right, isEmpty);
    });
  });

  group('openDetail (generic, registry-driven exclusive groups)', () {
    test(
      'a left room drops other room/session (liveView) but keeps the right',
      () {
        var loc = WorkspaceNav.openConstructDetail(
          u('/'),
          const PanelToken('vocab', 'a'),
          'vocab',
        );
        loc = WorkspaceNav.openExclusiveLeftRoom(
          u(loc),
          const PanelToken('room', '!a'),
        );
        loc = WorkspaceNav.openDetail(u(loc), const PanelToken('room', '!b'));
        final lists = parseOpenPanels(u(loc));
        expect(lists.left.where((t) => t.type == 'room').map((t) => t.param), [
          '!b',
        ]);
        // vocab is `detail`, room is `liveView` — no shared group, so it survives.
        expect(lists.right.any((t) => t.type == 'vocab'), isTrue);
      },
    );

    test(
      'a session (liveView+detail) drops both a room AND a vocab detail',
      () {
        var loc = WorkspaceNav.openConstructDetail(
          u('/'),
          const PanelToken('vocab', 'a'),
          'vocab',
        );
        loc = WorkspaceNav.openExclusiveLeftRoom(
          u(loc),
          const PanelToken('room', '!a'),
        );
        loc = WorkspaceNav.openDetail(
          u(loc),
          const PanelToken('session', '!s'),
        );
        final lists = parseOpenPanels(u(loc));
        expect(lists.left.where((t) => t.type == 'room'), isEmpty);
        expect(lists.left.single, const PanelToken('session', '!s'));
        expect(
          lists.right.any((t) => t.type == 'vocab' || t.type == 'grammar'),
          isFalse,
        );
      },
    );
  });

  group('pushPage / popPage (generic param push on a pushable panel)', () {
    test('push deepens the param; pop returns one level then to the root', () {
      var loc = WorkspaceNav.pushPage(u('/'), 'settingspage', 'security');
      expect(
        parseOpenPanels(u(loc)).right.single,
        const PanelToken('settingspage', 'security'),
      );
      loc = WorkspaceNav.pushPage(u(loc), 'settingspage', 'security/password');
      expect(
        parseOpenPanels(u(loc)).right.single,
        const PanelToken('settingspage', 'security/password'),
      );
      loc = WorkspaceNav.popPage(u(loc), 'settingspage', 'security/password');
      expect(
        parseOpenPanels(u(loc)).right.single,
        const PanelToken('settingspage', 'security'),
      );
      loc = WorkspaceNav.popPage(u(loc), 'settingspage', 'security');
      expect(
        parseOpenPanels(u(loc)).right.single,
        const PanelToken('settingspage'),
      );
    });

    test('pushing keeps other panels in the column', () {
      var loc = WorkspaceNav.openRight(
        u('/'),
        const PanelToken('analytics', 'vocab'),
      );
      loc = WorkspaceNav.pushPage(u(loc), 'settingspage', 'learning');
      final right = parseOpenPanels(u(loc)).right.map((t) => t.type).toSet();
      expect(right.containsAll({'analytics', 'settingspage'}), isTrue);
    });

    test('a course management page opens beside the card as a coursepage '
        'detail, keeping the map filter; one at a time; closing reveals the '
        'card', () {
      // The course workspace: a `?m=course:<id>` map filter + a left course
      // panel. A management button (Edit, Invite, …) opens beside the card.
      const base = '/?c=!s&left=course';
      var loc = WorkspaceNav.openCoursePage(u(base), 'edit');
      final left = parseOpenPanels(u(loc)).left;
      expect(left.map((t) => t.type).toList(), ['course', 'coursepage']);
      expect(left.last, const PanelToken('coursepage', 'edit'));
      // The course identity (the map filter) survives.
      expect(activeSpaceIdFor(u(loc)), '!s');
      // Opening a different management page replaces the first (one at a time).
      loc = WorkspaceNav.openCoursePage(u(loc), 'invite');
      expect(
        parseOpenPanels(
          u(loc),
        ).left.where((t) => t.type == 'coursepage').single,
        const PanelToken('coursepage', 'invite'),
      );
      // Closing the management detail drops it, leaving the card and filter.
      loc = WorkspaceNav.closeLeft(
        u(loc),
        const PanelToken('coursepage', 'invite'),
      );
      expect(parseOpenPanels(u(loc)).left.single, const PanelToken('course'));
      expect(activeSpaceIdFor(u(loc)), '!s');
    });

    test('openCoursePage(filter:) folds the invite contact filter into the '
        'coursepage token param instead of a loose ?filter= query', () {
      final loc = WorkspaceNav.openCoursePage(
        u('/?c=!s&left=course'),
        'invite',
        filter: 'knock',
      );
      final uri = u(loc);
      expect(uri.queryParameters['filter'], isNull);
      expect(
        parseOpenPanels(uri).left.where((t) => t.type == 'coursepage').single,
        const PanelToken('coursepage', 'invite/knock'),
      );
    });

    test(
      'openCoursePageFor opens a management page from ANYWHERE — setting the '
      'target space scope even from the bare map or a different course',
      () {
        // From the bare world map (no course scope at all).
        var loc = WorkspaceNav.openCoursePageFor(u('/'), '!target', 'invite');
        expect(activeSpaceIdFor(u(loc)), '!target');
        expect(parseOpenPanels(u(loc)).left.map((t) => t.type).toList(), [
          'course',
          'coursepage',
        ]);
        expect(
          parseOpenPanels(u(loc)).left.last,
          const PanelToken('coursepage', 'invite'),
        );
        // From a DIFFERENT course — the scope is replaced with the target's.
        loc = WorkspaceNav.openCoursePageFor(
          u('/?c=!other&left=course'),
          '!target',
          'edit',
        );
        expect(activeSpaceIdFor(u(loc)), '!target');
        expect(
          parseOpenPanels(
            u(loc),
          ).left.where((t) => t.type == 'coursepage').single,
          const PanelToken('coursepage', 'edit'),
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
        final loc = WorkspaceNav.openPractice(u(base), 'vocab');
        final lists = parseOpenPanels(u(loc));
        // The right column is just the practice panel — analytics + vocab gone.
        expect(lists.right.single, const PanelToken('practice', 'vocab'));
        // The left session (shares the detail slot) is dropped; the live room
        // (independent) stays.
        expect(lists.left.map((t) => t.type), ['room']);
      },
    );

    test(
      'opening a construct detail closes practice (one detail across columns)',
      () {
        final practice = WorkspaceNav.openPractice(u('/'), 'vocab');
        expect(
          parseOpenPanels(u(practice)).right.single,
          const PanelToken('practice', 'vocab'),
        );
        const vocab = PanelToken('vocab', '{"l":"x"}');
        final loc = WorkspaceNav.openConstructDetail(
          u(practice),
          vocab,
          'vocab',
        );
        final right = parseOpenPanels(u(loc)).right;
        // practice is gone; the vocab detail + its analytics master are seated.
        expect(right.any((t) => t.type == 'practice'), isFalse);
        expect(right.map((t) => t.type).toSet(), {'vocab', 'analytics'});
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
      expect(activityInfoFor(uri)?.id, 'act-123');
      expect(uri.queryParameters['activity'], isNull);
      // #7267: the activity REPLACES the panels, so no `left=course` card rides
      // beside it and no right panel survives.
      expect(WorkspaceQuery.valueOf(uri.query, 'right'), isNull);
      expect(parseOpenPanels(uri).left.map((t) => t.type), ['activity']);
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
