import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

void main() {
  AppSection section(String location) => sectionFor(Uri.parse(location));
  String? space(String location) => activeSpaceIdFor(Uri.parse(location));

  group('sectionFor', () {
    test('root selects world; the real /rooms routes select chats', () {
      expect(section('/'), AppSection.world);
      expect(section('/rooms/archive/!abc'), AppSection.chats);
    });

    test(
      'the real /courses routes select courses; retired paths are world',
      () {
        expect(section('/courses/own/plan-1'), AppSection.courses);
        expect(section('/courses/preview/!abc'), AppSection.courses);
        // Retired section paths have no redirects and no section identity: they
        // are dead links by design (routing.instructions.md).
        expect(section('/analytics'), AppSection.world);
        expect(section('/settings/security'), AppSection.world);
        expect(section('/profile'), AppSection.world);
        expect(section('/chats'), AppSection.world);
      },
    );

    test('first-class world objects (uuid) select world', () {
      expect(
        section('/32ad3c08-e501-41c5-b544-0875026090ed'),
        AppSection.world,
      );
    });

    test('exact segments only — no substring leakage', () {
      expect(section('/courses/analytics-course-name'), AppSection.courses);
    });

    test('an empty left column under a ?c= context selects courses', () {
      // The scoped-map backdrop: no left panel, so the course context is what
      // the rail highlights.
      expect(section('/?c=!s:x'), AppSection.courses);
      expect(section('/?c=!s:x&left=course'), AppSection.courses);
    });

    test('the global chat list wins over the course context (decision 5, '
        '#7467)', () {
      // The "click a quest then click chats, but the quest stays selected" bug:
      // the global chat LIST over a course-scoped map reads as Chats, not
      // Courses, even though `?c=` persists.
      expect(section('/?c=!s:x&left=chats'), AppSection.chats);
      expect(section('/?c=!s:x&left=chats,room:!r'), AppSection.chats);
    });

    test('a course room reads as its course, not the global chat list', () {
      // A room opened inside a course keeps the `?c=` context; the rail
      // highlights the COURSE whether its card is still beside the room
      // (left=course,room) or was closed (a lone room over `?c=`). Only a room
      // with NO course context is a direct chat. (The bug: the "chats OR room"
      // clause highlighted Chats while a course card was visibly open, #7467.)
      expect(section('/?c=!s:x&left=course,room:!r'), AppSection.courses);
      expect(section('/?c=!s:x&left=course:chat,room:!r'), AppSection.courses);
      expect(section('/?left=room:!r&c=!s:x'), AppSection.courses);
      expect(section('/?left=room:!r'), AppSection.chats); // no course context
    });

    test('section identity rides in the left token at the world path /', () {
      // The path collapses to `/`; the rail highlight derives from the token.
      expect(section('/?left=chats'), AppSection.chats);
      expect(section('/?left=chats,room:!a'), AppSection.chats);
      expect(section('/?left=room:!a'), AppSection.chats); // a lone live chat
      expect(section('/?left=addcourse'), AppSection.courses); // the hub
      expect(section('/?left=addcoursepage:own'), AppSection.courses); // a step
    });
  });

  group('activeSpaceIdFor (course is the ?c= context, not the path)', () {
    test('reads the course context from ?c=, anywhere in the query', () {
      expect(space('/?c=!s:x'), '!s:x');
      expect(space('/?c=%21abc'), '!abc'); // an encoded value decodes
      // independent of the path and of which panels happen to be open
      expect(space('/?left=room:!r&c=!s:x&right=analytics:vocab'), '!s:x');
    });

    test('no course context → null (world map)', () {
      expect(space('/'), isNull);
      expect(space('/?left=room:!r'), isNull); // a room token is not a course
      // The retired m=course: spelling is dead by design — no legacy reads.
      expect(space('/?m=course:!s'), isNull);
      expect(space('/courses/!s:x'), isNull); // paths never carry the context
    });
  });

  group('isMapHole (world_v2: only the world root is a map hole)', () {
    test('the world root is the map hole', () {
      expect(isMapHole('/'), isTrue);
    });

    test('every other route renders content, never a hole', () {
      // Every section is a token panel now — there are no /chats, /settings,
      // /analytics, or /profile render routes — so no path but `/` is a hole.
      // The remaining real routes are bounded details or full-bleed.
      expect(isMapHole('/settings'), isFalse);
      expect(isMapHole('/analytics/morph'), isFalse);
      expect(isMapHole('/courses'), isFalse);
      expect(isMapHole('/practice/vocab'), isFalse);
      expect(isMapHole('/rooms/archive/abc'), isFalse);
      expect(isMapHole(null), isFalse);
    });
  });

  group('shortRoomId / fullRoomId (URL display)', () {
    const domain = 'local.pangea.chat';

    test('round-trips a home-domain id to a bare localpart', () {
      const full = '!GLEFhPQklmQQYWYiWc:local.pangea.chat';
      final short = shortRoomId(full, domain: domain);
      expect(short, '!GLEFhPQklmQQYWYiWc');
      expect(fullRoomId(short, domain: domain), full);
    });

    test('leaves foreign-homeserver ids untouched (federation-safe)', () {
      const foreign = '!abc:matrix.org';
      expect(shortRoomId(foreign, domain: domain), foreign);
      expect(fullRoomId(foreign, domain: domain), foreign);
    });

    test('fullRoomId is a no-op on an id that already carries a domain', () {
      expect(
        fullRoomId('!x:local.pangea.chat', domain: domain),
        '!x:local.pangea.chat',
      );
    });

    test('helpers degrade gracefully when the home domain is unknown', () {
      // Pre-login / no global: ids pass through unchanged rather than throwing.
      expect(shortRoomId('!x:local.pangea.chat'), '!x:local.pangea.chat');
      expect(fullRoomId('!x'), '!x');
    });

    test('shortenHomeRoomIdsInUrl strips home domain across path + query', () {
      const d = 'local.pangea.chat';
      expect(
        shortenHomeRoomIdsInUrl('/rooms/!abc:local.pangea.chat', domain: d),
        '/rooms/!abc',
      );
      expect(
        shortenHomeRoomIdsInUrl(
          '/rooms/!abc:local.pangea.chat/details',
          domain: d,
        ),
        '/rooms/!abc/details',
      );
      expect(
        shortenHomeRoomIdsInUrl(
          '/courses/!s:local.pangea.chat?activity=x&roomid=!r:local.pangea.chat',
          domain: d,
        ),
        '/courses/!s?activity=x&roomid=!r',
      );
      // Foreign-homeserver ids keep their domain (federation-safe).
      expect(
        shortenHomeRoomIdsInUrl('/rooms/!abc:matrix.org', domain: d),
        '/rooms/!abc:matrix.org',
      );
    });
  });

  group('activeRoomIdFromPanels (#7208)', () {
    String? active(String location) =>
        activeRoomIdFromPanels(Uri.parse(location));

    test('no open room token yields null', () {
      expect(active('/?left=chats'), isNull);
      expect(active('/'), isNull);
    });

    test('the open room: token (beside the chat list) is the active room', () {
      expect(active('/?left=chats,room:!abc:server.org'), '!abc:server.org');
    });

    test('a foreign-homeserver room id is kept intact', () {
      expect(active('/?left=chats,room:!abc:matrix.org'), '!abc:matrix.org');
    });
  });

  // #7385: the activity plan is a first-class `left=activity:` panel token (no
  // longer the `?activity=` canvas overlay). It is a left-column `liveView`
  // sibling of `room`/`session`, so the parser keeps it like any registered panel
  // and enforces one-live-view exclusivity. `activityFor` reads this same token.
  group('activity left token (#7385)', () {
    List<PanelTypesEnum> leftTypes(String location) => [
      for (final t in parseOpenPanels(Uri.parse(location)).left) t.type,
    ];
    TokenParam? activityParam(String location) => parseOpenPanels(
      Uri.parse(location),
    ).left.firstWhere((t) => t.type == PanelTypesEnum.activity).param;

    test('an `activity` left token parses with its id as the param', () {
      expect(leftTypes('/?left=activity:abc'), [PanelTypesEnum.activity]);
      final param1 = activityParam('/?left=activity:abc');
      expect(param1, isA<ActivityTokenParam>());
      expect((param1 as ActivityTokenParam).activityId, 'abc');

      final param2 = activityParam(
        '/?m=course:!s&left=activity:32ad3c08-e501-41c5-b544-0875026090ed',
      );
      expect(param2, isA<ActivityTokenParam>());
      expect(
        (param2 as ActivityTokenParam).activityId,
        '32ad3c08-e501-41c5-b544-0875026090ed',
      );
    });

    test('activity and room are liveView siblings — only the first survives', () {
      // Opening an activity claims the single live view (a chat can\'t coexist).
      expect(leftTypes('/?left=activity:a,room:!r'), [PanelTypesEnum.activity]);
      expect(leftTypes('/?left=room:!r,activity:a'), [PanelTypesEnum.room]);
    });
  });
}
