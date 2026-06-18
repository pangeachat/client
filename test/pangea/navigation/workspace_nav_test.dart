import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

void main() {
  Uri u(String s) => Uri.parse(s);

  group('openRight / closeRight', () {
    test('adds a token and round-trips back through the parser', () {
      final loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('review', '!def'));
      expect(parseOpenPanels(u(loc)).right, [const PanelToken('review', '!def')]);
    });

    test('an encoded construct survives the add → URL → parse round-trip', () {
      const token = PanelToken('vocab', '{"lemma":"a,b","type":"verb"}');
      final loc = WorkspaceNav.openRight(u('/chats'), token);
      expect(parseOpenPanels(u(loc)).right.single, token);
    });

    test('atStart blooms a detail to the left of an existing summary', () {
      var loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.openRight(
        u(loc),
        const PanelToken('vocab', 'hablar'),
        atStart: true,
      );
      expect(parseOpenPanels(u(loc)).right.map((t) => t.type), ['vocab', 'analytics']);
    });

    test('adding an existing token is idempotent (deduped)', () {
      var loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('review', '!a'));
      loc = WorkspaceNav.openRight(u(loc), const PanelToken('review', '!a'));
      expect(parseOpenPanels(u(loc)).right.length, 1);
    });

    test('close removes the token; the key disappears when the list empties', () {
      final opened = WorkspaceNav.openRight(u('/chats'), const PanelToken('review', '!a'));
      final closed = WorkspaceNav.closeRight(u(opened), const PanelToken('review', '!a'));
      expect(parseOpenPanels(u(closed)).right, isEmpty);
      expect(closed, '/chats'); // no dangling ?right=
    });
  });

  group('preserves the rest of the URL', () {
    test('an unrelated query param is kept verbatim', () {
      final loc = WorkspaceNav.openRight(
        u('/courses/!s?activity=abc'),
        const PanelToken('analytics', 'sessions'),
      );
      final parsed = u(loc);
      expect(parsed.queryParameters['activity'], 'abc');
      expect(parseOpenPanels(parsed).right, [const PanelToken('analytics', 'sessions')]);
      expect(parsed.path, '/courses/!s');
    });

    test('the path is preserved', () {
      final loc = WorkspaceNav.openRight(u('/rooms/!abc'), const PanelToken('review', '!def'));
      expect(u(loc).path, '/rooms/!abc');
    });
  });

  group('setRight replaces the whole list (metric switch)', () {
    test('drops the old analytics/detail tokens and seats one summary', () {
      var loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.openRight(u(loc), const PanelToken('vocab', 'hablar'), atStart: true);
      loc = WorkspaceNav.setRight(u(loc), [const PanelToken('analytics', 'grammar')]);
      expect(parseOpenPanels(u(loc)).right, [const PanelToken('analytics', 'grammar')]);
    });
  });

  group('openExclusiveLeftRoom (one live session)', () {
    test('opening a room drops any other room but keeps chats/course', () {
      var loc = WorkspaceNav.setLeft(
        u('/chats'),
        const [PanelToken('chats'), PanelToken('room', '!a')],
      );
      loc = WorkspaceNav.openExclusiveLeftRoom(
        u(loc),
        const PanelToken('room', '!b'),
      );
      final left = parseOpenPanels(u(loc)).left;
      expect(
        left.where((t) => t.type == 'room').map((t) => t.param).toList(),
        ['!b'],
      );
      expect(left.any((t) => t.type == 'chats'), isTrue);
    });

    test('preserves an open right panel by construction', () {
      final loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/chats?right=analytics:vocab'),
        const PanelToken('room', '!a'),
      );
      expect(
        parseOpenPanels(u(loc)).right,
        [const PanelToken('analytics', 'vocab')],
      );
    });
  });

  group('openCourse (open / switch tab)', () {
    test('switching tabs replaces the course token rather than stacking', () {
      // The course id lives in the path; the token param is just the tab.
      var loc = WorkspaceNav.openCourse(
        u('/courses/!s'),
        const PanelToken('course', 'chat'),
      );
      loc = WorkspaceNav.openCourse(
        u(loc),
        const PanelToken('course', 'participants'),
      );
      final courses =
          parseOpenPanels(u(loc)).left.where((t) => t.type == 'course').toList();
      expect(courses.length, 1);
      expect(courses.single.param, 'participants');
    });

    test('keeps a live room beside the course (a course can scope a room)', () {
      var loc = WorkspaceNav.openExclusiveLeftRoom(
        u('/chats'),
        const PanelToken('room', '!a'),
      );
      loc = WorkspaceNav.openCourse(u(loc), const PanelToken('course', '!s'));
      final left = parseOpenPanels(u(loc)).left;
      expect(left.any((t) => t.type == 'room'), isTrue);
      expect(left.any((t) => t.type == 'course'), isTrue);
    });
  });

  group('openConstructDetail (one detail at a time, across columns)', () {
    test('a new construct detail replaces the prior one, keeping the summary', () {
      var loc = WorkspaceNav.openRight(u('/'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.openConstructDetail(
          u(loc), const PanelToken('vocab', 'hablar'), 'vocab');
      loc = WorkspaceNav.openConstructDetail(
          u(loc), const PanelToken('grammar', 'verb'), 'grammar');
      final right = parseOpenPanels(u(loc)).right;
      // exactly one construct detail, blooming left of its kept summary
      expect(right.where((t) => t.type == 'vocab' || t.type == 'grammar').length, 1);
      expect(right.first, const PanelToken('grammar', 'verb')); // detail at the edge-left
      expect(right.any((t) => t.type == 'analytics'), isTrue); // summary kept
    });

    test('cold start seats the detail AND its summary together', () {
      final loc = WorkspaceNav.openConstructDetail(
          u('/'), const PanelToken('vocab', 'hablar'), 'vocab');
      final right = parseOpenPanels(u(loc)).right;
      expect(right.map((t) => t.type), ['vocab', 'analytics']);
      expect(right.last.param, 'vocab'); // the seated summary's tab
    });

    test('opening a construct detail closes an open activity session', () {
      // session (left) + a vocab detail open: drilling a new construct drops the
      // session — one detail at a time across columns.
      var loc = WorkspaceNav.openExclusiveSession(
          u('/'), const PanelToken('session', '!s'));
      loc = WorkspaceNav.openConstructDetail(
          u(loc), const PanelToken('vocab', 'hablar'), 'vocab');
      final lists = parseOpenPanels(u(loc));
      expect(lists.left.any((t) => t.type == 'session'), isFalse); // session gone
      expect(lists.right.first, const PanelToken('vocab', 'hablar'));
    });

    test('a live room chat is NOT closed by opening a construct detail', () {
      var loc = WorkspaceNav.openExclusiveLeftRoom(
          u('/'), const PanelToken('room', '!live'));
      loc = WorkspaceNav.openConstructDetail(
          u(loc), const PanelToken('vocab', 'hablar'), 'vocab');
      final lists = parseOpenPanels(u(loc));
      expect(lists.left.any((t) => t.type == 'room'), isTrue); // chat survives
      expect(lists.right.first, const PanelToken('vocab', 'hablar'));
    });
  });

  group('openExclusiveSession (the session shares the detail slot)', () {
    test('opening a session drops an open vocab/grammar detail', () {
      var loc = WorkspaceNav.openConstructDetail(
          u('/'), const PanelToken('vocab', 'hablar'), 'vocab');
      loc = WorkspaceNav.openExclusiveSession(
          u(loc), const PanelToken('session', '!s'));
      final lists = parseOpenPanels(u(loc));
      expect(lists.right.any((t) => t.type == 'vocab' || t.type == 'grammar'),
          isFalse); // construct detail gone
      expect(lists.left.any((t) => t.type == 'session'), isTrue);
    });

    test('a session drops another room/session (one live view)', () {
      var loc = WorkspaceNav.openExclusiveLeftRoom(
          u('/'), const PanelToken('room', '!live'));
      loc = WorkspaceNav.openExclusiveSession(
          u(loc), const PanelToken('session', '!s'));
      final left = parseOpenPanels(u(loc)).left;
      expect(left.where((t) => t.type == 'room' || t.type == 'session').length, 1);
      expect(left.single, const PanelToken('session', '!s'));
    });
  });

  group('setLeft / clearLeft', () {
    test('setLeft replaces the whole left list, preserving right', () {
      var loc = WorkspaceNav.setLeft(
        u('/chats?right=analytics:vocab'),
        const [PanelToken('room', '!a'), PanelToken('chats')],
      );
      loc = WorkspaceNav.setLeft(u(loc), const [PanelToken('course')]);
      expect(parseOpenPanels(u(loc)).left, [const PanelToken('course')]);
      expect(
        parseOpenPanels(u(loc)).right,
        [const PanelToken('analytics', 'vocab')],
      );
    });

    test('clearLeft empties the left list but keeps right', () {
      final loc = WorkspaceNav.clearLeft(
        u('/chats?left=chats&right=analytics:vocab'),
      );
      expect(parseOpenPanels(u(loc)).left, isEmpty);
      expect(
        parseOpenPanels(u(loc)).right,
        [const PanelToken('analytics', 'vocab')],
      );
    });
  });

  group('closeSection (close a path-addressable section panel)', () {
    test('closing a course returns to the world map and keeps room + right', () {
      final loc = WorkspaceNav.closeSection(
        u('/courses/!s?left=course,room:!a&right=analytics:vocab'),
        const PanelToken('course'),
      );
      final parsed = u(loc);
      expect(parsed.path, '/'); // off the /courses/:id path so no route card
      final lists = parseOpenPanels(parsed);
      expect(lists.left, [const PanelToken('room', '!a')]); // room kept
      expect(lists.left.any((t) => t.type == 'course'), isFalse);
      expect(lists.right, [const PanelToken('analytics', 'vocab')]); // kept
    });

    test('closing the only panel lands on a bare world path', () {
      final loc = WorkspaceNav.closeSection(
        u('/courses/!s?left=course'),
        const PanelToken('course'),
      );
      expect(loc, '/');
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
      expect(
        parseOpenPanels(parsed).right,
        [const PanelToken('analytics', 'vocab')],
      );
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
    test('opens the menu as a right token, keeping other right panels', () {
      final loc = WorkspaceNav.openSettings(u('/?right=analytics:vocab'));
      final right = parseOpenPanels(u(loc)).right;
      expect(right.any((t) => t.type == 'settings' && t.param == null), isTrue);
      expect(right.any((t) => t.type == 'analytics'), isTrue);
    });

    test('opening a page seats it as a detail BESIDE the menu master', () {
      final loc = WorkspaceNav.openSettings(u('/'), page: 'learning');
      final right = parseOpenPanels(u(loc)).right;
      // page detail blooms at the front; the menu master is kept behind it.
      expect(right.map((t) => t.type), ['settingspage', 'settings']);
      expect(right.first.param, 'learning');
    });

    test('opening another page replaces the page detail (one at a time)', () {
      var loc = WorkspaceNav.openSettings(u('/'), page: 'security');
      loc = WorkspaceNav.openSettings(u(loc), page: 'security/password');
      final pages = parseOpenPanels(u(loc))
          .right
          .where((t) => t.type == 'settingspage')
          .toList();
      expect(pages.length, 1);
      expect(pages.single.param, 'security/password'); // slash survives
      expect(parseOpenPanels(u(loc)).right.any((t) => t.type == 'settings'),
          isTrue); // menu still there
    });

    test('settingsBack: a leaf pops to its parent page; a top-level page '
        'returns to the menu (drops the page detail)', () {
      final toSecurity = WorkspaceNav.settingsBack(
        u(WorkspaceNav.openSettings(u('/'), page: 'security/password')),
        'security/password',
      );
      expect(
        parseOpenPanels(u(toSecurity))
            .right
            .firstWhere((t) => t.type == 'settingspage')
            .param,
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
      var loc = WorkspaceNav.openRight(u('/'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.openSettings(u(loc), page: 'learning');
      loc = WorkspaceNav.closeSettings(u(loc));
      final right = parseOpenPanels(u(loc)).right;
      expect(right.any((t) => t.type == 'settings' || t.type == 'settingspage'),
          isFalse);
      expect(right.single, const PanelToken('analytics', 'vocab'));
    });
  });

  group('setSection (move between sections, keep the live chat)', () {
    test('moving to the world keeps the live room and the right column', () {
      final world = WorkspaceNav.setSection(
        u('/chats?left=chats,room:!a&right=analytics:vocab'),
        '/',
        null,
      );
      expect(u(world).path, '/');
      final lists = parseOpenPanels(u(world));
      expect(lists.left, [const PanelToken('room', '!a')]); // room kept, no section
      expect(lists.right, [const PanelToken('analytics', 'vocab')]); // kept
    });

    test('sets the new section in front of the kept room', () {
      final chats = WorkspaceNav.setSection(
        u('/?left=room:!a&right=analytics:vocab'),
        '/chats',
        const PanelToken('chats'),
      );
      expect(u(chats).path, '/chats');
      expect(
        parseOpenPanels(u(chats)).left,
        [const PanelToken('chats'), const PanelToken('room', '!a')],
      );
    });

    test('keepRoom:false drops the room (focused full-bleed flow)', () {
      final hub = WorkspaceNav.setSection(
        u('/chats?left=chats,room:!a&right=analytics:vocab'),
        '/courses',
        null,
        keepRoom: false,
      );
      expect(parseOpenPanels(u(hub)).left, isEmpty);
      expect(
        parseOpenPanels(u(hub)).right,
        [const PanelToken('analytics', 'vocab')],
      );
    });
  });

  group('openDetail (generic, registry-driven exclusive groups)', () {
    test('a left room drops other room/session (liveView) but keeps the right', () {
      var loc = WorkspaceNav.openConstructDetail(
          u('/'), const PanelToken('vocab', 'a'), 'vocab');
      loc = WorkspaceNav.openExclusiveLeftRoom(
          u(loc), const PanelToken('room', '!a'));
      loc = WorkspaceNav.openDetail(u(loc), const PanelToken('room', '!b'));
      final lists = parseOpenPanels(u(loc));
      expect(lists.left.where((t) => t.type == 'room').map((t) => t.param), ['!b']);
      // vocab is `detail`, room is `liveView` — no shared group, so it survives.
      expect(lists.right.any((t) => t.type == 'vocab'), isTrue);
    });

    test('a session (liveView+detail) drops both a room AND a vocab detail', () {
      var loc = WorkspaceNav.openConstructDetail(
          u('/'), const PanelToken('vocab', 'a'), 'vocab');
      loc = WorkspaceNav.openExclusiveLeftRoom(
          u(loc), const PanelToken('room', '!a'));
      loc = WorkspaceNav.openDetail(u(loc), const PanelToken('session', '!s'));
      final lists = parseOpenPanels(u(loc));
      expect(lists.left.where((t) => t.type == 'room'), isEmpty);
      expect(lists.left.single, const PanelToken('session', '!s'));
      expect(lists.right.any((t) => t.type == 'vocab' || t.type == 'grammar'),
          isFalse);
    });
  });

  group('pushPage / popPage (generic param push on a pushable panel)', () {
    test('push deepens the param; pop returns one level then to the root', () {
      var loc = WorkspaceNav.pushPage(u('/'), 'settingspage', 'security');
      expect(parseOpenPanels(u(loc)).right.single,
          const PanelToken('settingspage', 'security'));
      loc = WorkspaceNav.pushPage(u(loc), 'settingspage', 'security/password');
      expect(parseOpenPanels(u(loc)).right.single,
          const PanelToken('settingspage', 'security/password'));
      loc = WorkspaceNav.popPage(u(loc), 'settingspage', 'security/password');
      expect(parseOpenPanels(u(loc)).right.single,
          const PanelToken('settingspage', 'security'));
      loc = WorkspaceNav.popPage(u(loc), 'settingspage', 'security');
      expect(
          parseOpenPanels(u(loc)).right.single, const PanelToken('settingspage'));
    });

    test('pushing keeps other panels in the column', () {
      var loc = WorkspaceNav.openRight(u('/'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.pushPage(u(loc), 'settingspage', 'learning');
      final right = parseOpenPanels(u(loc)).right.map((t) => t.type).toSet();
      expect(right.containsAll({'analytics', 'settingspage'}), isTrue);
    });
  });
}
