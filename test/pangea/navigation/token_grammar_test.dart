import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

/// The token-grammar encoding contract (routing.instructions.md): params carry
/// open-ended, all-language content; every value round-trips the URL
/// losslessly; content never collides with the structural separators (comma,
/// colon, slash, and the `.` field separator).
void main() {
  Uri u(String location) => Uri.parse(location);

  group('TokenFields (the encoding contract)', () {
    const hostile = [
      'abrigadoro',
      'ir de compras', // multiword
      'a.b.c', // the field separator itself
      'a,b:c/d&e=f?', // every structural separator at once
      '汉语词典', // non-Latin script
      'עִברִית', // RTL with combining marks
      "l'été", // diacritics + apostrophe
      '%2E%25', // content that looks pre-encoded
      '🌍🎉', // emoji
      '.', // dot-only
    ];

    test('every hostile value round-trips a single field', () {
      for (final value in hostile) {
        expect(
          TokenFields.decode(TokenFields.encode(value)),
          value,
          reason: 'field round-trip failed for "$value"',
        );
      }
    });

    test('joined fields split back apart whatever their content', () {
      for (final a in hostile) {
        for (final b in hostile) {
          final param = TokenFields.join([
            TokenFields.encode(a),
            TokenFields.encode(b),
          ]);
          final fields = TokenFields.split(param);
          expect(fields.length, 2, reason: 'split count for "$a" + "$b"');
          expect(TokenFields.decode(fields[0]), a);
          expect(TokenFields.decode(fields[1]), b);
        }
      }
    });
  });

  group('construct tokens (compact, no JSON)', () {
    test('compact param round-trips through a full URL token list', () {
      for (final lemma in ['abrigadoro', 'ir de compras', 'a,b.c:d', '汉语']) {
        final construct = ConstructIdentifier(
          lemma: lemma,
          type: ConstructTypeEnum.vocab,
          category: 'adj',
        );
        final token = PanelToken(
          'vocab',
          VocabAnalyticsTokenParam.parse(construct.toTokenParam()),
        );
        // Through the list grammar and back — a comma inside a lemma can never
        // shatter the token list.
        final uri = u('/?right=analytics:vocab,${token.encode()}');
        final parsed = parseOpenPanels(uri).right;
        expect(parsed.length, 2, reason: 'list shattered for "$lemma"');
        final vocab = parsed.firstWhere((t) => t.type == 'vocab');
        final back = ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.vocab,
          vocab.param!.build(),
        );
        expect(back?.lemma, lemma);
        expect(back?.category, 'adj');
        expect(back?.type, ConstructTypeEnum.vocab);
      }
    });

    test(
      'the token type supplies the construct type — grammar means morph',
      () {
        final construct = ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.morph,
          'ser.aux',
        );
        expect(construct?.type, ConstructTypeEnum.morph);
        expect(construct?.lemma, 'ser');
        expect(construct?.category, 'aux');
      },
    );
  });

  group('malformed percent-encoding degrades, never throws', () {
    // `Uri.parse` normalizes a stray `%` in the URL (`%2` → `%252`), so the
    // crash risk is the SECOND decode layer: a hand-crafted `%252` becomes the
    // field `%2`, which `Uri.decodeComponent` then rejects. Every field
    // decoder must swallow that rather than abort the route.
    test('a token-list parse survives a malformed second-level field', () {
      // vocab:%252 → PanelToken param `%2` → the construct field decode throws
      // internally but is caught; the list still parses both tokens.
      final right = parseOpenPanels(
        u('/?right=analytics:vocab,vocab:%252'),
      ).right;
      expect(right.any((t) => t.type == 'analytics'), isTrue);
    });

    test('fromTokenParam degrades a malformed field without throwing; an '
        'empty param is null', () {
      // A malformed field decodes to its raw form (harmless), never a crash.
      expect(
        () => ConstructIdentifier.fromTokenParam(ConstructTypeEnum.vocab, '%2'),
        returnsNormally,
      );
      expect(
        ConstructIdentifier.fromTokenParam(ConstructTypeEnum.vocab, ''),
        isNull,
      );
    });

    test('TokenFields.decode degrades a malformed field to its raw form', () {
      expect(TokenFields.decode('%2'), '%2');
      expect(TokenFields.decode('ab%zz'), 'ab%zz');
    });

    test(
      'ActivityToken/RoomToken parse a malformed field without throwing',
      () {
        expect(() => ActivityTokenParam.parse('act-1.r%2'), returnsNormally);
        expect(() => RoomTokenParam.parse('!abc/e/%2'), returnsNormally);
      },
    );
  });

  group('ActivityToken (session bindings ride the fields)', () {
    test('id-only builds a bare param', () {
      expect(ActivityTokenParam(activityId: 'act-1').build(), 'act-1');
      final parsed = ActivityTokenParam.parse('act-1');
      expect(parsed.activityId, 'act-1');
      expect(parsed.roomId, isNull);
      expect(parsed.launch, isFalse);
      expect(parsed.autoplay, isNull);
    });

    test('all fields round-trip', () {
      final param = ActivityTokenParam(
        activityId: 'act-1',
        roomId: '!sess',
        launch: true,
        autoplay: 2,
      ).build();
      final parsed = ActivityTokenParam.parse(param);
      expect(parsed.activityId, 'act-1');
      expect(parsed.roomId, '!sess');
      expect(parsed.launch, isTrue);
      expect(parsed.autoplay, 2);
    });

    test('unknown fields are ignored (newer URL, older client)', () {
      final parsed = ActivityTokenParam.parse('act-1.zfuture.l');
      expect(parsed.activityId, 'act-1');
      expect(parsed.launch, isTrue);
    });
  });

  group(
    'RoomToken (event/filter fold into the room param, not loose query)',
    () {
      test('a bare id has no sub-page, filter, or eventId', () {
        expect(RoomTokenParam(id: '!abc').build(), '!abc');
        final parsed = RoomTokenParam.parse('!abc');
        expect(parsed.id, '!abc');
        expect(parsed.subpage, isNull);
        expect(parsed.filter, isNull);
        expect(parsed.eventId, isNull);
      });

      test('a plain sub-page (search, edit, …) round-trips with no filter', () {
        final param = RoomTokenParam(id: '!abc', subpage: 'search').build();
        expect(param, '!abc/search');
        final parsed = RoomTokenParam.parse(param);
        expect(parsed.id, '!abc');
        expect(parsed.subpage, 'search');
        expect(parsed.filter, isNull);
        expect(parsed.eventId, isNull);
      });

      test('an invite filter appends after the sub-page and round-trips', () {
        final param = RoomTokenParam(
          id: '!abc',
          subpage: 'invite',
          filter: 'knocking',
        ).build();
        expect(param, '!abc/invite/knocking');
        final parsed = RoomTokenParam.parse(param);
        expect(parsed.id, '!abc');
        expect(parsed.subpage, 'invite');
        expect(parsed.filter, 'knocking');
        expect(parsed.eventId, isNull);
      });

      test('a details page with no filter round-trips (edit/access/…)', () {
        final param = RoomTokenParam(
          id: '!abc',
          subpage: 'details/edit',
        ).build();
        expect(param, '!abc/details/edit');
        final parsed = RoomTokenParam.parse(param);
        expect(parsed.id, '!abc');
        expect(parsed.subpage, 'details/edit');
        expect(parsed.filter, isNull);
      });

      test(
        'a details/invite filter round-trips, keeping the details prefix',
        () {
          final param = RoomTokenParam(
            id: '!abc',
            subpage: 'details/invite',
            filter: 'participants',
          ).build();
          expect(param, '!abc/details/invite/participants');
          final parsed = RoomTokenParam.parse(param);
          expect(parsed.id, '!abc');
          expect(parsed.subpage, 'details/invite');
          expect(parsed.filter, 'participants');
        },
      );

      test('a jump-to-message eventId round-trips despite its hostile '
          r'characters ($, :, /)', () {
        const eventId = r'$abc123:matrix.org/weird';
        final param = RoomTokenParam(id: '!abc', eventId: eventId).build();
        expect(param, '!abc/e/${TokenFields.encode(eventId)}');
        final parsed = RoomTokenParam.parse(param);
        expect(parsed.id, '!abc');
        expect(parsed.subpage, isNull);
        expect(parsed.filter, isNull);
        expect(parsed.eventId, eventId);
      });

      test('eventId takes precedence over a subPage when both are passed', () {
        final param = RoomTokenParam(
          id: '!abc',
          subpage: 'search',
          eventId: r'$xyz',
        ).build();
        final parsed = RoomTokenParam.parse(param);
        expect(parsed.subpage, isNull);
        expect(parsed.eventId, r'$xyz');
      });

      test('a hostile filter value round-trips (comma, colon, dot, space)', () {
        const hostileFilters = ['a,b:c/d', 'a.b.c', 'ir de compras'];
        for (final filter in hostileFilters) {
          final param = RoomTokenParam(
            id: '!abc',
            subpage: 'invite',
            filter: filter,
          ).build();
          final parsed = RoomTokenParam.parse(param);
          expect(
            parsed.filter,
            filter,
            reason: 'filter round-trip failed for "$filter"',
          );
        }
      });

      test(
        'an id with a colon (foreign-homeserver form) is preserved whole',
        () {
          // Room ids never contain `/`, so the leading segment up to the first
          // `/` is always the whole id — including a foreign `!id:server` form.
          final param = RoomTokenParam(
            id: '!abc:example.org',
            subpage: 'search',
          ).build();
          final parsed = RoomTokenParam.parse(param);
          expect(parsed.id, '!abc:example.org');
          expect(parsed.subpage, 'search');
        },
      );
    },
  );

  group('the ?c= course context', () {
    test('c= carries the bare space id and decodes', () {
      expect(activeSpaceIdFor(u('/?c=!s&left=course')), '!s');
      expect(activeSpaceIdFor(u('/?c=%21abc')), '!abc');
      expect(activeSpaceIdFor(u('/?left=chats')), isNull);
    });
  });

  group('activityInfoFor (session bindings ride the token fields)', () {
    test('reads the token fields', () {
      final info = activityInfoFor(u('/?c=!s&left=activity:act-1.r!sess.l'));
      expect(info?.activityId, 'act-1');
      expect(info?.roomId, '!sess');
      expect(info?.launch, isTrue);
    });

    test('no activity token means no activity', () {
      expect(activityInfoFor(u('/?left=chats')), isNull);
    });
  });

  group('WorkspaceNav.openActivity / dropActivityOverlay', () {
    test(
      'openActivity keeps the context by default and seats a sole token',
      () {
        final loc = WorkspaceNav.openActivity(
          u('/?c=!s&left=course&right=analytics:vocab'),
          'act-1',
          roomId: '!sess',
        );
        final uri = u(loc);
        expect(activeSpaceIdFor(uri), '!s');
        expect(parseOpenPanels(uri).left.map((t) => t.type), ['activity']);
        expect(parseOpenPanels(uri).right.map((t) => t.type), ['analytics']);
        expect(activityInfoFor(uri)?.roomId, '!sess');
        expect(uri.queryParameters['roomid'], isNull);
      },
    );

    test('a world-map pin (no context) opens with none, so it closes to the '
        'map', () {
      // openActivity never sets or clears context; a world-map pin simply has
      // none, so the plan closes with an X to the map (no back-arrow target).
      final loc = WorkspaceNav.openActivity(u('/?left=chats'), 'act-1');
      final uri = u(loc);
      expect(activeSpaceIdFor(uri), isNull);
      expect(parseOpenPanels(uri).left.map((t) => t.type), ['activity']);
    });

    test('dropActivityOverlay keeps the context; reopenCourseCard reseats the '
        'card', () {
      final open = u('/?c=!s&left=activity:act-1.r!sess');
      final closed = u(WorkspaceNav.dropActivityOverlay(open));
      expect(activeSpaceIdFor(closed), '!s');
      expect(parseOpenPanels(closed).left, isEmpty);
      final backToCard = u(
        WorkspaceNav.dropActivityOverlay(open, reopenCourseCard: true),
      );
      expect(parseOpenPanels(backToCard).left.map((t) => t.type), ['course']);
    });
  });
}
