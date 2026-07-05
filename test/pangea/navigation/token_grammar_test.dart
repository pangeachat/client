import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/activity_token.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
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
        final token = PanelToken('vocab', construct.toTokenParam());
        // Through the list grammar and back — a comma inside a lemma can never
        // shatter the token list.
        final uri = u('/?right=analytics:vocab,${token.encode()}');
        final parsed = parseOpenPanels(uri).right;
        expect(parsed.length, 2, reason: 'list shattered for "$lemma"');
        final vocab = parsed.firstWhere((t) => t.type == 'vocab');
        final back = ConstructIdentifier.fromTokenParam('vocab', vocab.param!);
        expect(back?.lemma, lemma);
        expect(back?.category, 'adj');
        expect(back?.type, ConstructTypeEnum.vocab);
      }
    });

    test(
      'the token type supplies the construct type — grammar means morph',
      () {
        final construct = ConstructIdentifier.fromTokenParam(
          'grammar',
          'ser.aux',
        );
        expect(construct?.type, ConstructTypeEnum.morph);
        expect(construct?.lemma, 'ser');
        expect(construct?.category, 'aux');
      },
    );
  });

  group('ActivityToken (session bindings ride the fields)', () {
    test('id-only builds a bare param', () {
      expect(ActivityToken.build('act-1'), 'act-1');
      final parsed = ActivityToken.parse('act-1');
      expect(parsed.id, 'act-1');
      expect(parsed.roomId, isNull);
      expect(parsed.launch, isFalse);
      expect(parsed.autoplay, isNull);
    });

    test('all fields round-trip', () {
      final param = ActivityToken.build(
        'act-1',
        roomId: '!sess',
        launch: true,
        autoplay: 2,
      );
      final parsed = ActivityToken.parse(param);
      expect(parsed.id, 'act-1');
      expect(parsed.roomId, '!sess');
      expect(parsed.launch, isTrue);
      expect(parsed.autoplay, 2);
    });

    test('unknown fields are ignored (newer URL, older client)', () {
      final parsed = ActivityToken.parse('act-1.zfuture.l');
      expect(parsed.id, 'act-1');
      expect(parsed.launch, isTrue);
    });
  });

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
      expect(info?.id, 'act-1');
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
